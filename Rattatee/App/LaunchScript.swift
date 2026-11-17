import Foundation

/// Opens the app on a given tab and state, for the screenshots CI takes.
///
/// Nobody can look at a simulator from a cloud session, and a simulator
/// cannot go for a bike ride, so the build workflow launches the app several
/// times with launch arguments and photographs what it draws: `-kDemo
/// recording` puts a ride through Tallinn on the Record tab, mid-ride.
/// Launch arguments land in UserDefaults' argument domain, so nothing is
/// stored, and a staged ride is never written to disk or sent
/// (`Store.pretend`). `-hue plum` and `-look dark` are the keys the
/// colour and the background are kept under, so they need nothing here.
/// Nothing here runs for a rider, who never launches the
/// app with arguments.
enum LaunchScript {
    static var tab: Int { UserDefaults.standard.integer(forKey: "kTab") }
    /// `-kSheet search` opens the search over the Record tab.
    static var sheet: String? { UserDefaults.standard.string(forKey: "kSheet") }

    #if DEBUG
    /// `-kDoors YES` draws the Apple and Google buttons whatever the site
    /// says it offers, so they can be photographed.
    static var doors: Bool { UserDefaults.standard.bool(forKey: "kDoors") }

    /// `-kDemo <state>`: recording, paused, save, short, saved, kept, rides,
    /// and goal and going, which have somewhere to ride to.
    @MainActor
    static func stage(_ store: Store) {
        guard let demo = UserDefaults.standard.string(forKey: "kDemo") else { return }
        let now = Date()
        func ride(_ status: Ride.Status, name: String = "", metres: Double = 4200, seconds: Int = 1028,
                  ago: TimeInterval = 0, problem: String? = nil) -> Ride {
            let started = now.addingTimeInterval(-ago - Double(seconds))
            var ride = Ride(id: UUID().uuidString, started: started, status: status)
            ride.name = name
            ride.points = path(metres: metres, from: started, seconds: seconds)
            ride.before = seconds
            ride.problem = problem
            if status == .recording {
                ride.before = 0
                ride.since = started
            }
            return ride
        }
        // Somewhere to go, and a suggested way that runs on past where the
        // staged ride has got to.
        let ahead = path(metres: 2400, from: now, seconds: 540)
        var goal = Goal(spot: Spot(id: "paper-mill-coffee", name: "Paper Mill Coffee",
                                   detail: "Masina 20 · Coffee roastery",
                                   lat: ahead.last?.lat ?? 59.44, lng: ahead.last?.lng ?? 24.76, kind: .mine))
        goal.way = .found(Way(metres: 2400, seconds: 540, line: ahead.map(\.coordinate)))
        switch demo {
        case "goal":
            store.pretend([])
            store.goal = goal
        case "going":
            store.pretend([ride(.recording, metres: 1300, seconds: 312)])
            store.goal = goal
        case "recording": store.pretend([ride(.recording)])
        case "paused": store.pretend([ride(.paused)])
        case "save": store.pretend([ride(.finished, metres: 8600, seconds: 2040)])
        case "short": store.pretend([ride(.finished, metres: 400, seconds: 120)])
        case "saved":
            let done = ride(.saved, name: "Kalamaja", metres: 8600, seconds: 2040)
            store.pretend([done], shown: done.id)
        case "kept":
            let kept = ride(.waiting, name: "Kalamaja", metres: 8600, seconds: 2040, problem: "offline")
            store.pretend([kept], shown: kept.id)
        case "rides":
            store.pretend([
                ride(.waiting, name: "Kalamaja", metres: 8600, seconds: 2040, ago: 3600, problem: "offline"),
                ride(.saved, name: "Pirita", metres: 21300, seconds: 4320, ago: 2 * 86_400),
                ride(.saved, metres: 5100, seconds: 1140, ago: 3 * 86_400),
                ride(.refused, name: "Kadriorg", metres: 3900, seconds: 240, ago: 5 * 86_400, problem: "fast")
            ])
        default: store.pretend([])
        }
    }

    /// A line of about `metres` through the middle of Tallinn, a point every
    /// twelve metres, zig-zagging the way streets do.
    private static func path(metres: Double, from start: Date, seconds: Int) -> [Point] {
        let count = max(2, Int(metres / 12))
        var points: [Point] = []
        var lat = 59.4300, lng = 24.7300
        for i in 0..<count {
            // Twelve metres north-east or east by turns, a block at a time.
            let north = (i / 40) % 2 == 0
            lat += north ? 0.000108 : 0.000012
            lng += north ? 0.000030 : 0.000205
            points.append(Point(lat: Geo.round5(lat), lng: Geo.round5(lng),
                                t: start.timeIntervalSince1970 + Double(seconds) * Double(i) / Double(count),
                                acc: 5))
        }
        return points
    }
    #endif
}
