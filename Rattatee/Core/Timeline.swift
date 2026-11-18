import CoreLocation
import Foundation

/// One part of a ride's session: what the rider was doing from one moment
/// to another. The ride page lists them in order (`Views/RideView.swift`).
struct Part {
    enum Kind {
        /// On the bike and moving.
        case ride
        /// On foot: a stretch Finish set aside as walked or run (`Motion`).
        case walk
        /// Carried: a train, a bus or a car.
        case vehicle
        /// Standing for a short while — a crossing, a red light.
        case wait
        /// Standing for long enough to have been somewhere.
        case stop
    }

    let kind: Kind
    /// Seconds since 1970.
    let from: Double
    let to: Double
    /// How far it went; nought for standing.
    let metres: Double
    /// Where the rider stood, for a stop: a dot on the ride's map.
    var at: CLLocationCoordinate2D?

    var seconds: Double { max(0, to - from) }
}

/// A ride as the session it was, with nothing thrown away: rode, waited at
/// a crossing, rode, stopped somewhere for a quarter of an hour, took the
/// train, walked, rode home.
///
/// WHY
///
/// The owner rode twelve rides on 2026-11-17 and 18 and read them back out
/// of the database. Two things were wrong. A quarter of an hour inside a
/// shop was half a kilometre of riding that never happened: indoors the
/// phone's fix wanders fifteen or twenty metres, the recorder keeps a point
/// every twelve, and so the stop was thirty-two points zigzagging over a
/// patch fifty metres by eighty — counted in the distance, halving the
/// average, and sent to the website as a knot of lines where somebody had
/// stood. And a train was nothing at all: the recorder dropped every point
/// of it as too fast, so the ride began at the far station as if the rider
/// had been put down there. The owner's words: keep the movement, and show
/// what happened.
///
/// WHAT IS KEPT, AND WHERE
///
/// Riding is `Ride.points`, as ever, and is what is sent. Walking is in
/// `Ride.aside`, set aside at Finish by `Motion`. A vehicle is in
/// `Ride.aside` too, marked `vehicle` in `Ride.asideKinds`: the stretches
/// `Motion` said were driven, and the points the recorder would not keep as
/// riding (`Ride.carried` — too fast for a bike, or on the rails of a way
/// by train), which Finish gathers into runs here. Standing is not stored:
/// it is a leg between two ridden points that took a long time and went
/// nowhere, and `parts(of:)` reads it off the points each time. That is why
/// a stop's wandering is taken out of the points at Finish (`settled`): what
/// is left is the point the rider arrived at, the point they left from, and
/// the time between, which is exactly what a stop is.
///
/// None of it is sent but the riding. The server receives fewer points and
/// a shorter time, never a label and never a point of a walk, a train or a
/// stop — **Only the riding is sent** in the README.
enum Timeline {
    /// Standing this long is said, as waiting; shorter is part of riding.
    static let waitShortest = 30.0
    /// Standing this long is a stop: no red light lasts two minutes. A stop
    /// comes off the active time, where a wait does not — `Ride.leaveOut`.
    static let stopShortest = 120.0
    /// Points all within this of their middle are one place. The owner's
    /// stop wandered fifty metres from its middle at the worst.
    static let radius = 60.0
    /// A place with fewer points than this has no wandering to take out.
    static let driftPoints = 3
    /// Carried points further apart in time than this are two journeys.
    static let carriedBreak = 120.0
    /// A carried run shorter than this, in metres or in points, is the
    /// phone's fix jumping, not a train.
    static let carriedShortest = 300.0
    static let carriedPoints = 4
    /// A carried point is kept once this far from the last one: a train
    /// needs no point every twelve metres to be drawn.
    static let carriedStep = 50.0

    /// Whether the leg from `a` to `b` was standing: slower than `Insight`
    /// counts as moving.
    static func still(_ a: Point, _ b: Point) -> Bool {
        let dt = b.t - a.t
        return dt > 0 && Geo.metres(a, b) / dt < Insight.still
    }

    /// The points with the wandering of every stop taken out: where a run of
    /// them stayed within `radius` of its own middle for `stopShortest` or
    /// more, and went at least three times further than it got, only the
    /// first and the last are kept.
    ///
    /// Three times further than it got is what tells wandering from riding.
    /// A long red light is also two minutes within sixty metres, but its
    /// points go straight through; a fix wandering indoors goes five hundred
    /// metres to end seven from where it began. The run is trimmed to the
    /// points near its middle before it is judged, so the last metres ridden
    /// up to a door are not taken for part of standing behind it.
    ///
    /// Run again over points it has already settled, it finds nothing: a
    /// stop is then two points, and two is under `driftPoints`.
    static func settled(_ points: [Point]) -> [Point] {
        var out: [Point] = []
        var i = 0
        while i < points.count {
            var j = i
            var lat = points[i].lat, lng = points[i].lng
            while j + 1 < points.count {
                let n = Double(j - i + 1)
                let middle = Point(lat: lat / n, lng: lng / n, t: 0, acc: 0)
                guard Geo.metres(middle, points[j + 1]) <= radius else { break }
                j += 1
                lat += points[j].lat
                lng += points[j].lng
            }
            let n = Double(j - i + 1)
            let middle = Point(lat: lat / n, lng: lng / n, t: 0, acc: 0)
            var a = i, b = j
            while a < b && Geo.metres(middle, points[a]) > radius { a += 1 }
            while b > a && Geo.metres(middle, points[b]) > radius { b -= 1 }

            let stay = Array(points[a...b])
            if stay.count >= driftPoints,
               points[b].t - points[a].t >= stopShortest,
               Geo.metres(points[a], points[b]) * 3 <= Geo.length(stay) {
                out.append(contentsOf: points[i..<a])
                out.append(points[a])
                out.append(points[b])
                i = b + 1
            } else {
                out.append(points[i])
                i += 1
            }
        }
        return out
    }

    /// The carried points as the journeys they were: cut where two are more
    /// than `carriedBreak` apart in time, and only the runs long enough to
    /// have been a journey.
    static func runs(_ carried: [Point]) -> [[Point]] {
        var runs: [[Point]] = []
        var run: [Point] = []
        for p in carried {
            if let last = run.last, p.t - last.t > carriedBreak {
                runs.append(run)
                run = []
            }
            run.append(p)
        }
        if !run.isEmpty { runs.append(run) }
        return runs.filter { $0.count >= carriedPoints && span($0) >= carriedShortest }
    }

    /// How far a run goes from point to point, gaps and all: a train's
    /// points may be further apart than `Geo.gap`, which `Geo.length` skips.
    private static func span(_ points: [Point]) -> Double {
        guard points.count > 1 else { return 0 }
        var m = 0.0
        for i in 1..<points.count { m += Geo.metres(points[i - 1], points[i]) }
        return m
    }

    /// The seconds between `start` and `end` that fall in any of `spans`,
    /// counted once where two overlap, less whatever of them fell in a
    /// pause — a pause is not riding time to begin with.
    static func covered(_ spans: [(Double, Double)], from start: Double, to end: Double,
                        less pauses: [[Double]]) -> Double {
        let clipped = spans
            .map { (max($0.0, start), min($0.1, end)) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }
        var merged: [(Double, Double)] = []
        for s in clipped {
            if let last = merged.last, s.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, s.1)
            } else {
                merged.append(s)
            }
        }
        var total = 0.0
        for s in merged {
            var inside = s.1 - s.0
            for pause in pauses where pause.count == 2 {
                inside -= max(0, min(s.1, pause[1]) - max(s.0, pause[0]))
            }
            total += max(0, inside)
        }
        return total
    }

    /// The ride, part by part, in the order it happened.
    ///
    /// A leg across a gap, across a stretch set aside or across a pause ends
    /// one part of riding and begins the next, and is nobody's: the stretch
    /// set aside is a part of its own, and a pause is the rider saying
    /// nothing was happening.
    static func parts(of ride: Ride) -> [Part] {
        var parts: [Part] = []
        let aside = ride.aside ?? []
        for (k, stretch) in aside.enumerated() {
            guard let first = stretch.first, let last = stretch.last, last.t > first.t else { continue }
            parts.append(Part(kind: ride.asideKind(k), from: first.t, to: last.t,
                              metres: span(stretch), at: nil))
        }

        let pauses = ride.breaks ?? []
        let points = ride.points
        var from: Double?
        var to = 0.0
        var metres = 0.0
        func close() {
            if let began = from, metres > 0 {
                parts.append(Part(kind: .ride, from: began, to: to, metres: metres, at: nil))
            }
            from = nil
            metres = 0
        }
        for i in points.indices.dropFirst() {
            let a = points[i - 1], b = points[i]
            let d = Geo.metres(a, b)
            let dt = b.t - a.t
            let cut = d > Geo.gap
                || aside.contains(where: { s in s.contains { $0.t > a.t && $0.t < b.t } })
                || pauses.contains(where: { $0.count == 2 && $0[0] < b.t && $0[1] > a.t })
            if cut {
                close()
                continue
            }
            if dt >= waitShortest && still(a, b) {
                close()
                let stop = dt >= stopShortest
                parts.append(Part(kind: stop ? .stop : .wait, from: a.t, to: b.t, metres: 0,
                                  at: stop ? a.coordinate : nil))
                continue
            }
            if from == nil { from = a.t }
            metres += d
            to = b.t
        }
        close()
        return parts.sorted { $0.from < $1.from }
    }
}
