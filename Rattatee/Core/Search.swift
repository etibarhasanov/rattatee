import CoreLocation
import Foundation

/// Somewhere to ride to: a place off the website's search, a street off its
/// geocoder, something Google Maps was asked for, or a point on the map — a
/// place Apple's map names, tapped, or anywhere at all, held.
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
        /// Anywhere at all on the map, held: a dropped pin.
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

/// Which way a way bends at a corner: the website's own nine words, under
/// `steps` in /api/route. Each is one recording in `Voice/`, so a word the
/// website adds later is one this build does not know, and it is left out
/// rather than guessed at.
///
/// `tunnel` is one of the website's words and not a corner: where the way
/// goes into a tunnel, said so a rider in a pocket knows the dark ahead is
/// the way.
///
/// And `train`, which is not one of the website's words but this app's: the
/// corner where a way by train leaves the bike — the station — made here
/// out of the train in /api/v1/route's `trains`. It has no recording; the
/// row shows it and the phone's own voice reads it.
enum Turn: String {
    case left, right, straight, around, roundabout, arrive, tunnel, train
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
        case .tunnel: return "arrow.up"
        case .train: return "tram.fill"
        }
    }
}

/// One corner of a way: which way it bends, the street it is onto, the exit
/// of a roundabout where the router counted one (nought where it did not),
/// and how far along the way's own line the corner is. A train's corner
/// also carries which train, when and to where, for its words.
struct Step: Equatable {
    let turn: Turn
    let name: String
    let exit: Int
    let along: Double
    var train: [String: String] = [:]

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
        case .tunnel: return L.t("turnTunnel")
        case .train: return L.t("turnTrain", train)
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
    /// Where it is a way by train: what the card and the map say of it.
    /// Nil for a way that is all bike, which is nearly every one.
    var train: Train?
    /// What kind of way it is, where the website says. It says one thing
    /// now: `ridden: true` on the way people have ridden and held their
    /// pace on, which it puts first. The other four are `style`, a name the
    /// website gave every way for a day from 2026-11-19 and then took back.
    /// Nil for a way with no name, which is every way but a ridden one.
    var style: Style?

    enum Style: String { case ridden, fastest, safest, quietest, shortest }

    /// Further than this from the line is not on it: the turns stop, and
    /// `Store.follow` says the rider is off the way and, if they stay off,
    /// finds a new one.
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
            && a.train == b.train
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

/// A way by train, out of /api/v1/route's `trains`: ride to a station, the
/// train with the bike on it, ride on. The way's `line` is all three end to
/// end, so how much is left, the turns and being off the way all work along
/// it as along any way; this is what is said and drawn differently.
struct Train: Equatable {
    /// Which train, from and to which station, when it leaves, and when to
    /// set off to catch it — the clock in Tallinn, as the website says it.
    let name: String
    let from: String
    let to: String
    let at: String
    let leave: String
    /// The legs in order, to draw: a ride as any way, the rail orange.
    let legs: [(bike: Bool, line: [CLLocationCoordinate2D])]
    /// Where along the way's line the rail runs. A point kept there would
    /// be the train's, not the bike's, and `Store.add` keeps none.
    let rail: ClosedRange<Double>

    static func == (a: Train, b: Train) -> Bool {
        a.name == b.name && a.at == b.at && a.from == b.from && a.to == b.to
    }
}

/// Where the rider is going, if they said: the place, and the way there once
/// the site has answered with one.
struct Goal: Equatable {
    enum Finding: Equatable { case looking, found(Way), missing }
    var spot: Spot
    /// The way the rider is going by: the one chosen of `ways`.
    var way: Finding = .looking
    /// Every way the website answered, its first first: up to five, and
    /// mostly one. More than one is a choice on the card.
    var ways: [Way] = []
    /// Which of `ways` is chosen.
    var chosen = 0
    /// Whether the rider has left the way, and how: nil while they are on
    /// it. `Store.follow` keeps it.
    var lost: Lost?
    /// What `Store.follow` remembers between points about the way being
    /// ridden: where along it the last point was, how far of it has been
    /// ridden backwards in a row, and how many points in a row were off it.
    /// Started again with every new way.
    var along = 0.0
    var back = 0.0
    var astray = 0
    /// After a new way off the old one, while its others are still a choice:
    /// how far the ride was, in metres, when it opened. Nil the rest of the
    /// time, which is before a ride, after the choice is made, and whenever
    /// the website answered one way. `Store.pick` keeps it.
    var picking: Double?
    /// Which of `ways` the rider has been on alone — on it and off every
    /// other — and for how many points in a row, while `picking`.
    var aloneOn: Int?
    var alonePoints = 0
}

/// The rider has left the way to `Goal`, in one of two ways, and the row on
/// the riding screen says which in place of the next turn.
///
/// First it is only said: off by a street or turned round for a few dozen
/// metres is often on purpose — a shop, a shortcut, a closed path. Ridden
/// on until it is plainly not that, the app asks the website for a new way
/// from where the rider is and setting off the way they are riding, by
/// itself and with no button, since the phone is in a pocket. That is the
/// owner's word: say it, then recalculate once the rider is really going
/// wrong, in the direction they plainly want to go. Where the website has
/// more than one new way, all of them are offered, quietly, and the one the
/// rider rides on is the one they get: `Goal.picking`.
struct Lost: Equatable {
    enum Kind: Equatable { case off, back }
    var kind: Kind
    /// How far the ride was, in metres, when it was first said.
    let since: Double
    /// How far from the way the rider is, for "80 m from it".
    var metres: Double
    /// Asking the website for a new way right now.
    var finding = false
    /// The last time it was asked and answered nothing: tried again after
    /// `Store.rerouteEvery`.
    var failed: Date?
}

/// Search and go, on the website's own search.
///
/// Nothing here is Rattatee's. The places are `GET /api/places?q=`, the one
/// search of the city the website's find bar and the map app use; the streets
/// are `GET /api/geocode?q=` with `near`; the way and its turns are `GET /api/v1/route` with `mode=bike`,
/// or `GET /api/route` where that does not answer;
/// and what none of them knows is `POST /api/lookup`, the website's **Look
/// for it on Google Maps**, offered from five letters as it is there. A place
/// Google answers with is kept by the site, so the next search finds it
/// without the button — for this app, the map app and the website alike.
///
/// All of it needs a connection and none of it is needed to record: a search
/// that fails says so and Start still works.
enum Search {
    /// The fewest letters worth asking the website — one or two are
    /// answered by the phone alone, from where the rider has been and its
    /// copy of the places, which is a request saved at every search — and
    /// the fewest before Google is offered, the website's five.
    static let shortest = 3
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

    /// Streets, addresses and districts for these letters — anywhere in
    /// Estonia, nearest first, where the phone knows where the rider is, and
    /// Tallinn's where it does not. `near` goes to one decimal, about ten
    /// kilometres, which is all the website uses of it: finer would tell it
    /// where somebody is standing for nothing, and would make every rider's
    /// request a different address, so none was answered from its cache.
    static func streets(_ q: String, near: CLLocationCoordinate2D?) async throws -> [Spot] {
        var query = ["q": q]
        if let near {
            query["near"] = "\((near.latitude * 10).rounded() / 10),\((near.longitude * 10).rounded() / 10)"
        }
        guard let object = try await rows("api/geocode", query) as? [String: Any],
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
    /// `others` — up to two more, and mostly none — then its `trains`, at
    /// most two and mostly none, or nothing where the site finds no way at
    /// all.
    ///
    /// Asked of /api/v1/route, which is /api/route with a version on it and
    /// the trains. Where it does not answer — a website from before it, or
    /// a refusal — /api/route is asked as it always was, and the ways come
    /// without trains: a new app reads an old website. An app from before
    /// this asks /api/route alone and is never offered a train it could not
    /// draw.
    static func ways(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, heading: Int? = nil) async -> [Way] {
        var query = [
            "from": "\(Geo.round5(from.latitude)),\(Geo.round5(from.longitude))",
            "to": "\(Geo.round5(to.latitude)),\(Geo.round5(to.longitude))",
            "mode": "bike"
        ]
        // Asked mid-ride, the way is to set off the way the rider is going:
        // the website's `heading`, which one from before it simply ignores.
        if let heading { query["heading"] = "\(heading)" }
        var object = try? await rows("api/v1/route", query) as? [String: Any]
        if object?["version"] == nil { object = try? await rows("api/route", query) as? [String: Any] }
        guard let object, let first = way(object) else { return [] }
        // An answer from before the website offered others has no such
        // field, and is the one way.
        return [first] + (object["others"] as? [[String: Any]] ?? []).compactMap { way($0) }
            + (object["trains"] as? [[String: Any]] ?? []).compactMap { train($0) }
    }

    /// One of the website's `trains` as a way: its legs end to end as the
    /// line, the rides' turns placed along it with the first ride's arrival
    /// — at the station, which is not arriving — turned into the train's
    /// own corner. Nil for one in a shape this build does not know.
    private static func train(_ object: [String: Any]) -> Way? {
        guard let metres = object["meters"] as? Double, let seconds = object["seconds"] as? Double,
              let leave = object["leave"] as? String,
              let raws = object["legs"] as? [[String: Any]], !raws.isEmpty else { return nil }
        func coords(_ raw: [String: Any]) -> [CLLocationCoordinate2D] {
            (raw["line"] as? [[Double]] ?? []).compactMap { $0.count > 1 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
        }
        let legs: [(raw: [String: Any], bike: Bool, line: [CLLocationCoordinate2D])] =
            raws.map { (raw: $0, bike: $0["kind"] as? String == "bike", line: coords($0)) }
        guard let rail = legs.first(where: { $0.raw["kind"] as? String == "train" }), rail.line.count > 1,
              legs.allSatisfy({ $0.line.count > 1 }) else { return nil }

        var line: [CLLocationCoordinate2D] = []
        var start = 0.0
        var railFrom = 0.0, railTo = 0.0
        var steps: [Step] = []
        let said = ["line": rail.raw["name"] as? String ?? "", "at": rail.raw["at"] as? String ?? "",
                    "to": rail.raw["to"] as? String ?? ""]
        for (i, leg) in legs.enumerated() {
            let length = Geo.length(leg.line.map { Point(lat: $0.latitude, lng: $0.longitude, t: 0, acc: 0) })
            if leg.bike {
                // Each ride's turns placed on that ride alone, so a turn
                // cannot snap to another part of the trip that passes by.
                let ride = Way(metres: length, seconds: 0, line: leg.line)
                for raw in leg.raw["steps"] as? [[String: Any]] ?? [] {
                    guard let step = ride.step(raw) else { continue }
                    if step.turn == .arrive && i < legs.count - 1 { continue }
                    steps.append(Step(turn: step.turn, name: step.name, exit: step.exit, along: step.along + start))
                }
            } else {
                railFrom = start
                railTo = start + length
                steps.append(Step(turn: .train, name: "", exit: 0, along: start, train: said))
            }
            line += leg.line
            start += length
        }
        var way = Way(metres: metres, seconds: Int(seconds), line: line, steps: steps.sorted { $0.along < $1.along })
        way.train = Train(name: said["line"] ?? "", from: rail.raw["from"] as? String ?? "", to: said["to"] ?? "",
                          at: said["at"] ?? "", leave: leave, legs: legs.map { (bike: $0.bike, line: $0.line) },
                          rail: railFrom...railTo)
        return way
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
        // Until this read `ridden`, the ridden way came first with a button
        // like any other's: the website had stopped sending `style`.
        way.style = (object["style"] as? String).flatMap(Way.Style.init(rawValue:))
            ?? (object["ridden"] as? Bool == true ? Way.Style.ridden : nil)
        return way
    }
}
