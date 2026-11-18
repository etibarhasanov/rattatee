import CoreMotion
import Foundation

/// Which stretches of a ride were not ridden: walked, run, or driven.
///
/// WHY IT IS ASKED ONCE, AT FINISH
///
/// The rider presses Start at the door and Finish at the next one, and in
/// between they may push the bike up a hill, walk it through a market or
/// carry it into a shop. Those stretches are not bike routes, and the rides
/// are collected to become a map of bike routes, so they are set aside — on
/// the phone, before anything is sent. They are kept there and drawn on the
/// ride's map, dotted (`Ride.aside`), but never counted as riding. The
/// server receives the same request it always has, with fewer points in it:
/// never a label saying what the rider was doing, never the points set aside.
///
/// The iPhone's motion coprocessor notes all day long whether its owner is
/// walking, running, cycling, in a car or still, and keeps a week of it,
/// whether or not any app is listening. So nothing listens while the ride
/// is recorded: at Finish the app asks once for what was noted between
/// Start and now, and that one question is the whole cost. It also covers a
/// ride whose app was killed half way, since the coprocessor was not.
///
/// The live numbers while riding stay over the whole time (option A, chosen
/// by the owner); the save card is where the walking comes out.
///
/// WHAT COUNTS AS NOT RIDING
///
/// A stretch the phone was at least fairly sure was walking, running or
/// driving, and not cycling, lasting `shortest` or more — so a few seconds
/// of "walking" at a slow corner, which the coprocessor does say, are
/// ridden. Still and unknown are ridden: a red light is part of a ride.
///
/// And a walk faster than `walkingFastest` is not a walk. Cycling is the
/// activity the coprocessor is least sure of with the phone in a pocket, and
/// the GPS knows better: if the points of a "walking" stretch went by at
/// bike speed, they are kept. Driving is not checked that way — a bike in
/// a car is not a bike route at any speed.
///
/// With no coprocessor, or the question refused under Settings, there is
/// nothing to ask and no walk is set aside. A train and a stop are found
/// without it, from the points alone — `Timeline`.
enum Motion {
    /// Not ridden for less than this, and it was ridden.
    static let shortest: TimeInterval = 60
    /// Faster than this over a "walking" stretch, in m/s, and it was ridden.
    static let walkingFastest: Double = 10 / 3.6

    private static let manager = CMMotionActivityManager()

    static var available: Bool {
        CMMotionActivityManager.isActivityAvailable()
            && ![.denied, .restricted].contains(CMMotionActivityManager.authorizationStatus())
    }

    /// Ask iOS the Motion & Fitness question, if it never has, so it is
    /// asked at Start rather than at Finish, when the rider is reading the
    /// numbers. A query is the only way to ask; this one is for a second.
    static func askOnce() {
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .notDetermined else { return }
        let now = Date()
        manager.queryActivityStarting(from: now.addingTimeInterval(-1), to: now, to: .main) { _, _ in }
    }

    /// One stretch the coprocessor said was not riding, in seconds since 1970.
    struct Stretch: Equatable {
        var from: Double
        var to: Double
        /// Driven rather than walked or run: not checked against the GPS.
        var driven: Bool
    }

    /// The stretches between `from` and `to` that were not ridden, by the
    /// coprocessor alone — `notRidden(_:by:)` then weighs them against the
    /// points. Empty when there is nothing to ask, or nothing came back.
    static func stretches(from: Date, to: Date) async -> [Stretch] {
        guard available, to > from else { return [] }
        let activities: [CMMotionActivity] = await withCheckedContinuation { done in
            manager.queryActivityStarting(from: from, to: to, to: .main) { found, _ in
                done.resume(returning: found ?? [])
            }
        }
        return stretches(activities.map {
            Noted(start: $0.startDate.timeIntervalSince1970,
                  away: ($0.walking || $0.running || $0.automotive) && !$0.cycling && $0.confidence != .low,
                  driven: $0.automotive)
        }, until: to.timeIntervalSince1970)
    }

    /// One thing the coprocessor noted, from its start until the next one's.
    struct Noted {
        var start: Double
        var away: Bool
        var driven: Bool
    }

    /// Runs of "away" joined into stretches, each ending where the next
    /// noted thing begins, the short ones dropped. Kept apart from the
    /// query so it reads without a phone.
    static func stretches(_ noted: [Noted], until end: Double) -> [Stretch] {
        var found: [Stretch] = []
        for (k, n) in noted.enumerated() where n.away {
            let to = k + 1 < noted.count ? noted[k + 1].start : end
            guard to > n.start else { continue }
            if var last = found.last, last.to >= n.start, last.driven == n.driven {
                last.to = to
                found[found.count - 1] = last
            } else {
                found.append(Stretch(from: n.start, to: to, driven: n.driven))
            }
        }
        return found.filter { $0.to - $0.from >= shortest }
    }

    /// The stretches that stand once the points have had their say: a walk
    /// whose points went by at bike speed was a ride the phone misread.
    static func notRidden(_ stretches: [Stretch], by points: [Point]) -> [Stretch] {
        stretches.filter { s in
            if s.driven { return true }
            let inside = points.filter { $0.t >= s.from && $0.t <= s.to }
            guard let first = inside.first, let last = inside.last, last.t > first.t else { return true }
            return Geo.length(inside) / (last.t - first.t) <= walkingFastest
        }
    }
}
