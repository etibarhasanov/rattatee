import CoreLocation
import Foundation

/// Somewhere to ride to: a place off the website's search, a street off its
/// geocoder, something Google Maps was asked for, or a point tapped on the
/// map — a place Apple's map names, or anywhere at all.
struct Spot: Identifiable, Equatable, Codable {
    /// Written to the phone by name (`Recents`): a case renamed is a place
    /// somebody chose that no longer reads back.
    enum Kind: String, Codable {
        /// On the Tallinn Tastebuds map: `map: true` in a row of /api/places.
        case mine
        /// One of the city's other venues, out of the same search.
        case place
        /// A street, an address or a district, from /api/geocode.
        case street
        /// What Google Maps just answered with, through /api/lookup.
        case google
        /// A place Apple's map names, tapped, that the website does not know.
        case apple
        /// Anywhere else tapped on the map.
        case pin
    }

    let id: String
    let name: String
    /// The address, and what kind of place it is where the site says. A pin
    /// learns its address a moment after it is dropped.
    var detail: String
    let lat: Double
    let lng: Double
    let kind: Kind

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    /// On the website's roll under this id — the map's own places, the
    /// export and what Google has answered — so a list can take it as it is.
    /// The rest have to be added as somebody's own place first.
    var onRoll: Bool { [.mine, .place, .google].contains(kind) }
}

/// Which way a way bends at a corner: the website's own eight words, under
/// `steps` in /api/route. Each is one recording in `Voice/`, so a word the
/// website adds later is one this build does not know, and it is left out
/// rather than guessed at.
enum Turn: String {
    case left, right, straight, around, roundabout, arrive
    case keepLeft = "keep-left"
    case keepRight = "keep-right"

    /// The arrow in the row.
    var symbol: String {
        switch self {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .keepLeft: return "arrow.up.left"
        case .keepRight: return "arrow.up.right"
        case .straight: return "arrow.up"
        case .around: return "arrow.uturn.down"
        case .roundabout: return "arrow.triangle.2.circlepath"
        case .arrive: return "flag.checkered"
        }
    }
}

/// One corner of a way: which way it bends, the street it is onto, the exit
/// of a roundabout where the router counted one (nought where it did not),
/// and how far along the way's own line the corner is.
struct Step: Equatable {
    let turn: Turn
    let name: String
    let exit: Int
    let along: Double

    /// What the row says, and what is said aloud where there is no
    /// recording. Key by key, so the strings check in CI sees each.
    var words: String {
        switch turn {
        case .left: return L.t("turnLeft")
        case .right: return L.t("turnRight")
        case .keepLeft: return L.t("turnKeepLeft")
        case .keepRight: return L.t("turnKeepRight")
        case .straight: return L.t("turnStraight")
        case .around: return L.t("turnAround")
        case .roundabout: return exit > 0 ? L.t("turnRoundaboutExit", ["n": "\(exit)"]) : L.t("turnRoundabout")
        case .arrive: return L.t("turnArrive")
        }
    }
}

/// A suggested way by bike, from /api/route.
struct Way: Equatable {
    let metres: Double
    let seconds: Int
    let line: [CLLocationCoordinate2D]
    /// Where it turns, in the order the corners come. Empty for a way the
    /// website answered before it sent any, which is then a line and silent.
    var steps: [Step] = []

    /// Further than this from the line is not on it: the row goes away and
    /// nothing is said until the rider is back.
    static let astray: Double = 60

    /// Where a point is on the way: how far along the line the nearest spot
    /// on it is, and how far off the point is from that spot. Measured to
    /// the segments and not the vertices, because a straight street is two
    /// vertices however long it is.
    func place(of here: CLLocationCoordinate2D) -> (along: Double, off: Double) {
        guard line.count > 1 else { return (0, .infinity) }
        // Flat metres around the point: good to a few centimetres across a city.
        let north = 111_320.0, east = 111_320.0 * cos(here.latitude * .pi / 180)
        func flat(_ p: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((p.longitude - here.longitude) * east, (p.latitude - here.latitude) * north)
        }
        var best = (along: 0.0, off: Double.infinity)
        var run = 0.0
        var a = flat(line[0])
        for i in 1..<line.count {
            let b = flat(line[i])
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            let t = length > 0 ? min(1, max(0, -(a.x * dx + a.y * dy) / (length * length))) : 0
            let px = a.x + t * dx, py = a.y + t * dy
            let off = (px * px + py * py).squareRoot()
            if off < best.off { best = (run + t * length, off) }
            run += length
            a = b
        }
        return best
    }

    /// The corner coming up from a point, and how far along the way it is —
    /// or nothing off the way, past the last corner, or on a way with none.
    func next(from here: CLLocationCoordinate2D) -> (step: Step, metres: Double)? {
        guard !steps.isEmpty else { return nil }
        let spot = place(of: here)
        guard spot.off <= Self.astray, let step = steps.first(where: { $0.along > spot.along }) else { return nil }
        return (step, step.along - spot.along)
    }

    /// One of the website's steps, placed on this way's line.
    func step(_ raw: [String: Any]) -> Step? {
        guard let word = raw["turn"] as? String, let turn = Turn(rawValue: word),
              let at = raw["at"] as? [Double], at.count > 1 else { return nil }
        let spot = place(of: CLLocationCoordinate2D(latitude: at[0], longitude: at[1]))
        guard spot.off <= Self.astray else { return nil }
        return Step(turn: turn, name: raw["name"] as? String ?? "", exit: raw["exit"] as? Int ?? 0, along: spot.along)
    }

    static func == (a: Way, b: Way) -> Bool {
        a.metres == b.metres && a.seconds == b.seconds && a.line.count == b.line.count && a.steps == b.steps
    }

    /// How much of the way is left from a point: the way from its vertex
    /// nearest the point to its end. Good to a street's width, which is all
    /// "1.1 km left" claims.
    func left(from here: CLLocationCoordinate2D) -> Double {
        guard line.count > 1 else { return 0 }
        func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            Geo.metres(Point(lat: a.latitude, lng: a.longitude, t: 0, acc: 0),
                       Point(lat: b.latitude, lng: b.longitude, t: 0, acc: 0))
        }
        var nearest = 0
        var best = Double.infinity
        for (i, p) in line.enumerated() {
            let d = metres(here, p)
            if d < best { best = d; nearest = i }
        }
        var rest = best
        if nearest + 1 < line.count {
            for i in (nearest + 1)..<line.count { rest += metres(line[i - 1], line[i]) }
        }
        return rest
    }
}

/// Where the rider is going, if they said: the place, and the way there once
/// the site has answered with one.
struct Goal: Equatable {
    enum Finding: Equatable { case looking, found(Way), missing }
    var spot: Spot
    /// The way the rider is going by: the one chosen of `ways`.
    var way: Finding = .looking
    /// Every way the website answered, its first first: up to three, and
    /// mostly one. More than one is a choice on the card.
    var ways: [Way] = []
    /// Which of `ways` is chosen.
    var chosen = 0
}

/// Search and go, on the website's own search.
///
/// Nothing here is Rattatee's. The places are `GET /api/places?q=`, the one
/// search of the city the website's find bar and the map app use; the streets
/// are `GET /api/geocode?q=`; the way and its turns are `GET /api/route` with `mode=bike`;
/// and what none of them knows is `POST /api/lookup`, the website's **Look
/// for it on Google Maps**, offered from five letters as it is there. A place
/// Google answers with is kept by the site, so the next search finds it
/// without the button — for this app, the map app and the website alike.
///
/// All of it needs a connection and none of it is needed to record: a search
/// that fails says so and Start still works.
enum Search {
    /// The fewest letters worth asking the website — one letter is answered
    /// by the phone alone, from where the rider has been and its copy of
    /// the places — and the fewest before Google is offered, the website's
    /// five.
    static let shortest = 2
    static let googleFrom = 5

    struct Failed: Error {}

    private static func rows(_ path: String, _ query: [String: String]) async throws -> Any {
        try JSONSerialization.jsonObject(with: try await API.data(path, query))
    }

    private static func spot(_ row: [String: Any], kind: Spot.Kind? = nil) -> Spot? {
        guard let id = row["id"] as? String, let name = row["name"] as? String,
              let lat = row["lat"] as? Double, let lng = row["lng"] as? Double else { return nil }
        let parts = [row["address"] as? String, row["category"] as? String].compactMap { $0 }.filter { !$0.isEmpty }
        // "Masina 20, 10144 Tallinn" reads better without the postcode and
        // the city every result shares.
        let detail = parts.map { $0.replacingOccurrences(of: #", \d{5} Tallinn$"#, with: "", options: .regularExpression) }
            .joined(separator: " · ")
        return Spot(id: id, name: name, detail: detail, lat: lat, lng: lng,
                    kind: kind ?? ((row["map"] as? Bool ?? false) ? .mine : .place))
    }

    /// The website's places for these letters, nearest first where it knows
    /// where the rider is.
    static func places(_ q: String, near: CLLocationCoordinate2D?) async throws -> [Spot] {
        var query = ["q": q, "limit": "12"]
        if let near { query["near"] = "\(Geo.round5(near.latitude)),\(Geo.round5(near.longitude))" }
        guard let list = try await rows("api/places", query) as? [[String: Any]] else { throw Failed() }
        return list.compactMap { spot($0) }
    }

    /// Streets, addresses and districts for these letters.
    static func streets(_ q: String) async throws -> [Spot] {
        guard let object = try await rows("api/geocode", ["q": q]) as? [String: Any],
              let list = object["results"] as? [[String: Any]] else { throw Failed() }
        return list.enumerated().compactMap { i, row in
            guard let lat = row["lat"] as? Double, let lng = row["lng"] as? Double,
                  let label = row["label"] as? String else { return nil }
            return Spot(id: "street-\(i)-\(lat)-\(lng)", name: label, detail: row["where"] as? String ?? "",
                        lat: lat, lng: lng, kind: .street)
        }
    }

    /// Whether Look for it on Google Maps can be offered at all. Asked once
    /// a launch, and only when somebody has typed enough letters for the
    /// button: most searches end at the second or third.
    @MainActor private static var ready: Bool?

    @MainActor
    static func googleReady() async -> Bool {
        if let ready { return ready }
        guard let object = try? await rows("api/lookup", [:]) as? [String: Any] else { return false }
        let answer = object["ready"] as? Bool ?? false
        ready = answer
        return answer
    }

    enum Looked {
        case found([Spot])
        /// Google has nothing in Tallinn for it.
        case nothing
        /// The day's budget is gone, or Google did not answer.
        case resting
        /// The site has no key: the button goes away.
        case off
    }

    static func google(_ q: String) async -> Looked {
        guard let object = try? await API.postObject("api/lookup", ["q": q]) else { return .resting }
        if object["ok"] as? Bool ?? false {
            let found = (object["places"] as? [[String: Any]] ?? []).compactMap { spot($0, kind: .google) }
            return found.isEmpty ? .nothing : .found(found)
        }
        return object["why"] as? String == "no-key" ? .off : .resting
    }

    /// The suggested ways by bike, the website's first first and then its
    /// `others` — up to two more, and mostly none — or nothing where the
    /// site finds no way at all.
    static func ways(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> [Way] {
        let query = [
            "from": "\(Geo.round5(from.latitude)),\(Geo.round5(from.longitude))",
            "to": "\(Geo.round5(to.latitude)),\(Geo.round5(to.longitude))",
            "mode": "bike"
        ]
        guard let object = try? await rows("api/route", query) as? [String: Any],
              let first = way(object) else { return [] }
        // An answer from before the website offered others has no such
        // field, and is the one way.
        return [first] + (object["others"] as? [[String: Any]] ?? []).compactMap { way($0) }
    }

    /// One way as the website sends it: `meters`, `seconds` and `line`.
    private static func way(_ object: [String: Any]) -> Way? {
        guard let metres = object["meters"] as? Double,
              let line = object["line"] as? [[Double]], line.count > 1 else { return nil }
        var way = Way(metres: metres, seconds: Int(object["seconds"] as? Double ?? 0),
                      line: line.compactMap { $0.count > 1 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil })
        // Where it turns, for the row while riding and the voice. A website
        // from before it sent any answers none, and the way is still a way.
        let steps = (object["steps"] as? [[String: Any]] ?? []).compactMap { way.step($0) }
        way.steps = steps.sorted { $0.along < $1.along }
        return way
    }
}
