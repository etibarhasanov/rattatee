import Foundation
import Observation

/// The signed-in rider's lists on the website, and putting a place on one.
///
/// A list is the website's (`/api/lists`): a name somebody chose, places off
/// the roll behind `/api/places`, published under their username. The app
/// does one thing with them — Add to a list, on the card of somewhere to go
/// — so it keeps only what that needs: each list's id, its name and how many
/// places are on it.
///
/// TWO KINDS OF PLACE
///
/// A place off the website's search, or one a tap on the map found in the
/// phone's copy of the roll, is on the roll already and goes on a list as it
/// is. A place only Apple's map names, or a pin, is not: it is added first as
/// the rider's own place (`action: place` with a name and a point), the
/// website's way of letting somebody put on a list a place the roll does
/// not have. It is seen only on their lists, and it does not touch Google.
///
/// KEPT ON THE PHONE UNTIL IT IS SENT
///
/// The lists are kept on the phone as they were last read, so the picker
/// works with no signal. An add that cannot reach the website waits on the
/// phone the way a ride does, and goes when the rides go — the app coming to
/// the front, or the network coming back (`Store.sendWaiting`), and so does
/// one the website answered with a 5xx. An add it refuses with a 4xx (signed
/// out, a full list) is dropped: sending it again would be refused again. One gap, the rides' own: an own place whose
/// answer was lost is made a second time on the next try.
@MainActor
@Observable
final class ListBook {
    static let shared = ListBook()

    struct Row: Codable, Identifiable, Equatable {
        let id: String
        let title: String
        var n: Int
    }

    /// One add the website has not had yet.
    struct Waiting: Codable, Equatable {
        let list: String
        /// The roll's id, or nil for a place to be added as the rider's own.
        let place: String?
        let name: String
        let address: String
        let lat: Double
        let lng: Double
    }

    enum Outcome: Equatable {
        case added
        /// No signal: on the phone, and sent later.
        case waiting
        /// The website's word for why not.
        case refused(String)
    }

    private(set) var lists: [Row] = []
    private(set) var waiting: [Waiting] = []
    @ObservationIgnored private var sending = false

    private static var listsFile: URL { Disk.support.appendingPathComponent("lists.json") }
    private static var waitingFile: URL { Disk.support.appendingPathComponent("lists-waiting.json") }

    private init() {
        lists = Self.read([Row].self, Self.listsFile) ?? []
        waiting = Self.read([Waiting].self, Self.waitingFile) ?? []
    }

    /// Read the rider's lists from the website. Throws with no signal, and
    /// the lists kept from last time stay.
    func load() async throws {
        let data = try await API.data("api/lists")
        let object = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rows = (object["lists"] as? [[String: Any]] ?? []).compactMap { row -> Row? in
            guard let id = row["id"] as? String, let title = row["title"] as? String else { return nil }
            return Row(id: id, title: title, n: row["n"] as? Int ?? 0)
        }
        lists = rows
        Self.write(rows, Self.listsFile)
    }

    /// Make a new list, empty, and put it first.
    func create(title: String) async throws -> Row {
        let answer = try await API.postObject("api/lists", ["action": "create", "title": title])
        guard let id = answer["id"] as? String else { throw API.Refusal(code: "busy", status: 0) }
        let row = Row(id: id, title: answer["title"] as? String ?? title, n: 0)
        lists.insert(row, at: 0)
        Self.write(lists, Self.listsFile)
        return row
    }

    /// Put a place on a list, now if the website can be reached and later if
    /// it cannot.
    func add(_ spot: Spot, name: String, to list: Row) async -> Outcome {
        let add = Waiting(list: list.id, place: spot.onRoll ? spot.id : nil,
                          name: name, address: spot.detail, lat: spot.lat, lng: spot.lng)
        do {
            try await send(add)
            return .added
        } catch let refusal as API.Refusal where refusal.status < 500 {
            return .refused(refusal.code)
        } catch {
            // No signal, or the website having a bad moment (a 5xx): later.
            waiting.append(add)
            Self.write(waiting, Self.waitingFile)
            return .waiting
        }
    }

    /// Send whatever is waiting, in the order it was added. After a failure
    /// the next try waits, a minute doubling to six hours, as a waiting
    /// ride does — A RIDE THAT FAILS WAITS LONGER EACH TIME in Store.swift —
    /// unless `now`, a person asking. Kept in memory: a relaunch starts the
    /// wait again, which is one request.
    func sendWaiting(now: Bool = false) async {
        guard !sending, !waiting.isEmpty else { return }
        if !now, let notBefore, notBefore > Date() { return }
        sending = true
        defer { sending = false }
        while let next = waiting.first {
            do {
                try await send(next)
            } catch let refusal as API.Refusal where refusal.status < 500 {
                // Refused for good: dropped, below.
            } catch {
                // No signal, or a 5xx: try again later.
                failures += 1
                notBefore = Date().addingTimeInterval(Store.retryWait(failures))
                return
            }
            failures = 0
            notBefore = nil
            waiting.removeFirst()
            Self.write(waiting, Self.waitingFile)
        }
    }
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var notBefore: Date?

    /// Signed out: the lists were somebody's, and so were the adds.
    func forget() {
        lists = []
        waiting = []
        try? FileManager.default.removeItem(at: Self.listsFile)
        try? FileManager.default.removeItem(at: Self.waitingFile)
    }

    private func send(_ add: Waiting) async throws {
        var place = add.place
        if place == nil {
            let answer = try await API.postObject("api/lists", [
                "action": "place", "name": add.name, "address": add.address, "lat": add.lat, "lng": add.lng
            ])
            place = (answer["place"] as? [String: Any])?["id"] as? String
        }
        guard let place else { throw API.Refusal(code: "place", status: 0) }
        try await API.post("api/lists", ["action": "add", "id": add.list, "place": place])
        if let i = lists.firstIndex(where: { $0.id == add.list }) {
            lists[i].n += 1
            Self.write(lists, Self.listsFile)
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func write<T: Encodable>(_ value: T, _ url: URL) {
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: url, options: .atomic) }
    }
}
