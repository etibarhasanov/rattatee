import Foundation

/// What a ride's points say beyond its distance and time: each kilometre's
/// time, the fastest one, the speed along the way, and how long was spent
/// standing. The ride page draws it (`Views/RideView.swift`), and its time
/// standing and fastest kilometre go to the website in every save's
/// `summary` (`Ride.summary`), for a signed-in account's totals.
///
/// The website works out the same for a ride it keeps — `rideInsight()` in
/// its `functions/api/_rides.js` — and this is that function, step for step
/// and constant for constant, so a ride reads alike here, on the website and
/// in the map app. It is worked out here rather than asked for because most
/// rides here are saved with no account, and the website answers a ride's
/// page only to the account it is filed under; and because the phone has the
/// whole ride, ends and all, where the website keeps it less 200 m at each.
///
/// Two differences, both because the phone has more than the website does.
/// A leg across a gap (`Geo.gap`) or across a stretch Finish set aside as
/// walked or driven is not counted at all, neither its metres nor its time,
/// as `Geo.length` does not count it: the website never receives one, since
/// it cuts the line there. And there is no top speed: the save card's
/// `Ride.topSpeed` is the one this app shows, and two top speeds on one page
/// would disagree.
struct Insight {
    struct Split: Hashable {
        let km: Int
        let metres: Double
        let seconds: Double
        var kmh: Double { seconds > 0 ? metres / seconds * 3.6 : 0 }
    }

    /// The speed over the stretch ending `at` metres along.
    struct Speed: Hashable {
        let at: Double
        let kmh: Double
    }

    /// Seconds spent standing: legs slower than `still`.
    let stopped: Double
    /// The fastest whole kilometre, or nil for a ride under one.
    let fastest: Split?
    /// Each kilometre's moving time; the last one however long it is.
    let splits: [Split]
    let speed: [Speed]

    /// Slower than this, in metres a second, a leg is standing — `STILL`.
    static let still = 1.0
    /// The speed is said every this many metres — `SPEED_STEP` — or every
    /// `stepShort` on a ride under `shortRide`, so a short one has a line.
    static let step = 500.0
    static let stepShort = 250.0
    static let shortRide = 5000.0

    /// Nil for a ride with nothing to work out: under two points, or no
    /// metres or no moving time between them.
    init?(_ ride: Ride) {
        let points = ride.points
        let aside = ride.aside ?? []
        guard points.count > 1 else { return nil }

        // How far along and how long riding by each point. A still leg adds
        // its time to `stopped` and neither its time nor its metres here.
        // Until 2026-11-22 it added its metres all the same, covered in no
        // moving time: some 12 m of drift at every red light, so a kilometre
        // with a light read a few seconds quick, and a pause the phone was
        // carried 231 m through, short of `Geo.gap`, put all 231 in no time.
        // On the website, whose `rideInsight()` had the same line, a ride
        // with 34 minutes of riding answered a top speed of 253 km/h that
        // day; it was fixed the same way in the same hour. So the kilometres
        // here are the ones ridden, a few metres short of the ride's
        // distance, and the `fastest` every save sends (`Ride.summary`) is
        // as honest as the page; its `stopped` was right all along.
        var along = [0.0], moving = [0.0]
        var stopped = 0.0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            var d = Geo.metres(a, b)
            var dt = max(0, b.t - a.t)
            if d > Geo.gap || aside.contains(where: { s in s.contains { $0.t > a.t && $0.t < b.t } }) {
                d = 0; dt = 0
            }
            let still = dt > 0 && d / dt < Self.still
            if still { stopped += dt }
            along.append(along[i - 1] + (still ? 0 : d))
            moving.append(moving[i - 1] + (still ? 0 : dt))
        }
        let total = along[along.count - 1]
        guard total > 0, moving[moving.count - 1] > 0 else { return nil }

        // The moving time at a distance along the line, between the two
        // points either side of it. Asked with distances that only grow, so
        // `k` walks forward once per pass.
        var k = 1
        func timeAt(_ m: Double) -> Double {
            while k < along.count - 1 && along[k] < m { k += 1 }
            let a = along[k - 1], b = along[k]
            let f = b > a ? (m - a) / (b - a) : 1
            return moving[k - 1] + (moving[k] - moving[k - 1]) * min(1, max(0, f))
        }

        var splits: [Split] = []
        var was = 0.0, end = 0.0
        var mark = 1000.0
        while was < total {
            let to = min(mark, total)
            let t = timeAt(to)
            splits.append(Split(km: splits.count + 1, metres: (to - was).rounded(), seconds: (t - end).rounded()))
            end = t
            was = to
            mark += 1000
        }

        var speed: [Speed] = []
        let step = total < Self.shortRide ? Self.stepShort : Self.step
        k = 1
        var from = 0.0, fromT = 0.0
        mark = step
        while from < total {
            let to = min(mark, total)
            let t = timeAt(to)
            // A last stretch under half a step is too short to say a speed.
            if to - from >= step / 2 && t > fromT {
                speed.append(Speed(at: to.rounded(), kmh: ((to - from) / (t - fromT) * 3.6 * 10).rounded() / 10))
            }
            from = to
            fromT = t
            mark += step
        }

        self.stopped = stopped.rounded()
        self.splits = splits
        self.fastest = splits.filter { $0.metres >= 1000 && $0.seconds > 0 }.min { $0.seconds < $1.seconds }
        self.speed = speed
    }
}

/// What the website keeps of a saved ride, `GET /api/rides/<id>`: its line,
/// with the first and last 200 m off, and its length. Only its rider's
/// account can ask, so it is there for a ride saved signed in and nowhere
/// else; the rest of what that route answers is worked out on the phone
/// instead (`Insight`).
struct Kept: Decodable {
    let meters: Double
    let line: [[Double]]

    private struct Answer: Decodable { let ride: Kept }

    /// The ride as the website keeps it, or nil: signed out, saved with no
    /// account, deleted on the website, or no signal. Nil is never an error
    /// worth saying — the page is the phone's ride either way.
    static func of(_ ride: Ride) async -> Kept? {
        guard ride.status == .saved, let id = ride.serverId,
              let data = try? await API.data("api/rides/\(id)") else { return nil }
        return (try? JSONDecoder().decode(Answer.self, from: data))?.ride
    }
}
