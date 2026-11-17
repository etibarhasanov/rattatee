import CoreLocation
import Foundation
import Observation

/// Every place the website's search knows, kept on the phone as a name and a
/// pin, so Where to? has something to show the moment it opens and while the
/// typing is still on its way to the site.
///
/// WHERE IT COMES FROM
///
/// `GET /api/places` with no query is the website's whole roll — the map's
/// own places merged over the Google Places export, the same eleven hundred
/// rows its find bar and the list picker fold in the browser. It is about
/// 75 KB over the wire. The phone keeps four things of each row — the id, the
/// name, where it is, and whether it is on the map — and leaves the rest
/// (addresses, kitchens, ratings) to the live search, which answers with
/// them a moment later. So the file on the phone is a list of pins with
/// names, and a row chosen from it is the same `Spot` the live search would
/// have answered with, under the same id.
///
/// WHEN IT IS ASKED FOR
///
/// Once when the app opens if the copy on the phone is missing or older than
/// a week, and never otherwise: the roll changes when the export is
/// refreshed or a place is added, which is weeks apart. A place added
/// yesterday is not on the phone yet, and the live search finds it the
/// moment somebody types. Asking costs nothing to record and a failure costs
/// nothing at all: the phone keeps what it had.
@MainActor
@Observable
final class Venues {
    static let shared = Venues()

    struct Venue: Codable {
        let id: String
        let name: String
        let lat: Double
        let lng: Double
        /// On the Tallinn Tastebuds map, rather than one of the city's others.
        let map: Bool
    }

    /// How old the copy may get before it is asked for again.
    static let week: TimeInterval = 7 * 86_400

    private(set) var all: [Venue] = []
    /// Each name folded the way a search is (`fold`), in the order of `all`.
    @ObservationIgnored private var keys: [String] = []
    @ObservationIgnored private var asking = false

    private static var file: URL {
        Disk.support.appendingPathComponent("venues.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let list = try? JSONDecoder().decode([Venue].self, from: data) {
            keep(list)
        }
    }

    private func keep(_ list: [Venue]) {
        all = list
        keys = list.map { Self.fold($0.name) }
    }

    /// Ask the site for the roll if the phone's copy is missing or a week old.
    func refresh() async {
        guard !asking else { return }
        let modified = (try? FileManager.default.attributesOfItem(atPath: Self.file.path))?[.modificationDate] as? Date
        if !all.isEmpty, let modified, Date().timeIntervalSince(modified) < Self.week { return }
        asking = true
        defer { asking = false }
        guard let data = try? await API.data("api/places"),
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
        let list: [Venue] = rows.compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String,
                  let lat = row["lat"] as? Double, let lng = row["lng"] as? Double else { return nil }
            return Venue(id: id, name: name, lat: lat, lng: lng, map: row["map"] as? Bool ?? false)
        }
        // An empty answer is the site having a bad moment, not Tallinn
        // having no places: keep what the phone had.
        guard !list.isEmpty, let out = try? JSONEncoder().encode(list) else { return }
        try? out.write(to: Self.file, options: .atomic)
        keep(list)
    }

    /// The places nearest a point, nearest first. Without a point, the
    /// places on the map, A to Z: something worth choosing from rather than
    /// the first twenty of eleven hundred.
    func nearest(_ here: CLLocationCoordinate2D?, count: Int = 20) -> [Spot] {
        guard let here else {
            return all.filter(\.map)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .prefix(count).map(Self.spot)
        }
        return all.map { ($0, Self.metres(here, $0)) }
            .sorted { $0.1 < $1.1 }
            .prefix(count).map { Self.spot($0.0) }
    }

    /// The places whose names hold these letters — a name starting with them
    /// first, then a word in it starting with them, then anywhere — and
    /// within each, nearest first where the phone knows where it is. Folded
    /// as the website folds its roll, so "pohjala" finds Põhjala.
    func matching(_ q: String, near here: CLLocationCoordinate2D?, count: Int = 12) -> [Spot] {
        let needle = Self.fold(q)
        guard !needle.isEmpty else { return [] }
        var hits: [(venue: Venue, rank: Int, metres: Double)] = []
        for (i, key) in keys.enumerated() {
            guard let range = key.range(of: needle) else { continue }
            let rank: Int
            if range.lowerBound == key.startIndex { rank = 0 }
            else if key[key.index(before: range.lowerBound)] == " " { rank = 1 }
            else { rank = 2 }
            let venue = all[i]
            hits.append((venue, rank, here.map { Self.metres($0, venue) } ?? 0))
        }
        return hits.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.metres < $1.metres }
            .prefix(count).map { Self.spot($0.venue) }
    }

    /// The place on the roll that a place tapped on Apple's map is, if it
    /// is one: within a street's width, with the one name holding the other
    /// ("Põhjala" and "Põhjala Tap Room"). So a tap on a café the website
    /// knows is that café, under the website's id, with no network at all.
    func same(as name: String, at point: CLLocationCoordinate2D) -> Spot? {
        let key = Self.fold(name)
        guard !key.isEmpty else { return nil }
        var best: (Venue, Double)?
        for (i, venue) in all.enumerated() {
            let other = keys[i]
            guard other.contains(key) || key.contains(other) else { continue }
            let d = Self.metres(point, venue)
            if d <= 80, d < (best?.1 ?? .infinity) { best = (venue, d) }
        }
        return best.map { Self.spot($0.0) }
    }

    private static func spot(_ venue: Venue) -> Spot {
        Spot(id: venue.id, name: venue.name, detail: "", lat: venue.lat, lng: venue.lng,
             kind: venue.map ? .mine : .place)
    }

    private static func metres(_ here: CLLocationCoordinate2D, _ venue: Venue) -> Double {
        Geo.metres(Point(lat: here.latitude, lng: here.longitude, t: 0, acc: 0),
                   Point(lat: venue.lat, lng: venue.lng, t: 0, acc: 0))
    }

    /// Lower case, no accents, anything that is not a letter or a digit a
    /// space: "Põhjala Tap Room" and "pohjala-tap" meet in the middle.
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let spaced = String(plain.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }
}
