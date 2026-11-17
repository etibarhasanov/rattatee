import CoreLocation
import Foundation

/// Somewhere to ride to: a place off the website's search, a street off its
/// geocoder, or something Google Maps was asked for.
struct Spot: Identifiable, Equatable {
    enum Kind {
        /// On the Tallinn Tastebuds map: `map: true` in a row of /api/places.
        case mine
        /// One of the city's other venues, out of the same search.
        case place
        /// A street, an address or a district, from /api/geocode.
        case street
        /// What Google Maps just answered with, through /api/lookup.
        case google
    }

    let id: String
    let name: String
    /// The address, and what kind of place it is where the site says.
    let detail: String
    let lat: Double
    let lng: Double
    let kind: Kind

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// A suggested way by bike, from /api/route.
struct Way: Equatable {
    let metres: Double
    let seconds: Int
    let line: [CLLocationCoordinate2D]

    static func == (a: Way, b: Way) -> Bool {
        a.metres == b.metres && a.seconds == b.seconds && a.line.count == b.line.count
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
    let spot: Spot
    var way: Finding = .looking
}

/// Search and go, on the website's own search.
///
/// Nothing here is Rattatee's. The places are `GET /api/places?q=`, the one
/// search of the city the website's find bar and the map app use; the streets
/// are `GET /api/geocode?q=`; the way is `GET /api/route` with `mode=bike`;
/// and what none of them knows is `POST /api/lookup`, the website's **Look
/// for it on Google Maps**, offered from five letters as it is there. A place
/// Google answers with is kept by the site, so the next search finds it
/// without the button — for this app, the map app and the website alike.
///
/// All of it needs a connection and none of it is needed to record: a search
/// that fails says so and Start still works.
enum Search {
    /// The fewest letters worth a search, and the fewest before Google is
    /// offered — the website's five.
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

    /// Whether Look for it on Google Maps can be offered at all.
    static func googleReady() async -> Bool {
        guard let object = try? await rows("api/lookup", [:]) as? [String: Any] else { return false }
        return object["ready"] as? Bool ?? false
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

    /// The suggested way by bike, or nil where the site finds none.
    static func way(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> Way? {
        let query = [
            "from": "\(Geo.round5(from.latitude)),\(Geo.round5(from.longitude))",
            "to": "\(Geo.round5(to.latitude)),\(Geo.round5(to.longitude))",
            "mode": "bike"
        ]
        guard let object = try? await rows("api/route", query) as? [String: Any],
              let metres = object["meters"] as? Double,
              let line = object["line"] as? [[Double]], line.count > 1 else { return nil }
        return Way(metres: metres, seconds: Int(object["seconds"] as? Double ?? 0),
                   line: line.compactMap { $0.count > 1 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil })
    }
}
