import Foundation
import Observation

/// Where the rider has gone before: the last few places they chose, newest
/// first, kept on the phone and nowhere else.
///
/// Where to? opens on the last three of these and nothing else, because
/// somewhere a rider has been is far likelier to be where they are going
/// than the nearest café. They also answer the first letter typed
/// — "p" finds the Põhjala they rode to last week before anything else is
/// asked of anybody.
///
/// A dropped pin is not kept: "Dropped pin" three times over is not a
/// history. Everything else chosen is — a search row, a street, a place
/// tapped on the map — as the `Spot` it was, so choosing it again is the
/// same as choosing it the first time and asks the website only for the way.
@MainActor
@Observable
final class Recents {
    static let shared = Recents()

    /// How many are kept, and how many Where to? shows before a letter.
    static let kept = 12
    static let shown = 3

    private(set) var all: [Spot] = []

    private static var file: URL {
        Disk.support.appendingPathComponent("recents.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.file),
           let list = try? JSONDecoder().decode([Spot].self, from: data) {
            all = list
        }
    }

    /// Put a place chosen just now on top, once.
    func add(_ spot: Spot) {
        guard spot.kind != .pin else { return }
        all.removeAll { Self.same($0, spot) }
        all.insert(spot, at: 0)
        if all.count > Self.kept { all.removeLast(all.count - Self.kept) }
        save()
    }

    func remove(_ spot: Spot) {
        all.removeAll { $0.id == spot.id }
        save()
    }

    /// The ones whose names hold these letters, newest first.
    func matching(_ q: String) -> [Spot] {
        let needle = Venues.fold(q)
        guard !needle.isEmpty else { return [] }
        return all.filter { Venues.fold($0.name).contains(needle) }
    }

    /// The same place twice: the same id, or the same name on the same
    /// spot — a street's id carries where it stood in one search's answer,
    /// so the same street found twice has two.
    private static func same(_ a: Spot, _ b: Spot) -> Bool {
        a.id == b.id || (a.name == b.name && a.lat == b.lat && a.lng == b.lng)
    }

    private func save() {
        guard let out = try? JSONEncoder().encode(all) else { return }
        try? out.write(to: Self.file, options: .atomic)
    }
}
