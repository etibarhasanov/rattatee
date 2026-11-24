import Foundation

/// Where the website's own account is while it rides, for the pin on the map
/// at tallinntastebuds.ee that says "last seen here, on a bike".
///
/// ONE ACCOUNT, AND NOBODY ELSE'S RIDE
///
/// The owner asked for it on 2026-11-24: the site's own account,
/// `tallinntastebuds`, shown on the site's map while it is out on a ride.
/// The website says which account that is — `shares` on `GET /api/account`,
/// true for that one and absent for every other (`Store.shares`) — and
/// refuses a spot from anybody else. So this runs on one phone. On every
/// other it is never fed a point and nothing is sent.
///
/// WHERE A RIDE BEGINS AND ENDS NEVER LEAVES THE PHONE
///
/// A ride begins and ends at somebody's door, and a map anybody can open
/// must not say whose. The website takes 200 m off each end of a ride it
/// keeps (`Geo.ends`), and this is the same 200 m held back while the ride
/// is still going on, which only the phone can do: no server knows where a
/// ride will end.
///
///  - A spot is sent only once the rider is `Geo.ends` of riding past it. So
///    the pin trails the rider, about forty seconds at a bike's pace, and
///    the last 200 m before Pause or Finish are never sent at all: they were
///    still waiting when it was pressed, and `stop()` drops them.
///  - Nothing within `Geo.ends`, in a straight line, of a `door` is sent: where
///    the ride began, where it was paused and where it was resumed. The
///    first 200 m of riding are always inside that, and so is a loop that
///    comes back past the start.
///  - Only inside Tallinn's box, which is the city that map is of.
///
/// ONE SPOT, AND NOT OFTEN
///
/// The website keeps one spot and writes each over the last, so there is no
/// queue here either: a spot that did not go, for want of a signal or any
/// other reason, is dropped and the next one says more. A spot is sent when
/// the rider passed it at least `every` seconds after the last one sent and
/// `moved` metres from it, which is one request for about every hundred
/// metres of riding: at most 180 an hour, from one phone. The site's side
/// is `functions/api/seen.js`, and **Last seen, on a bike** in its handbook.
struct Live {
    /// Seconds between the spots sent, by when the rider passed each, and
    /// how far apart they have to be.
    static let every: TimeInterval = 20
    static let moved: Double = 25
    /// A spot passed longer ago than this is not where anybody was last
    /// seen: the phone stood still, unpaused, and has only now moved on. The
    /// website refuses one past fifteen minutes — `LATE` in its `seen.js`.
    static let stale: TimeInterval = 600

    /// The points of this run the rider is not yet `Geo.ends` past, oldest
    /// first, each with how far into the run it was ridden. A run is the
    /// riding since Start, a Resume or a gap.
    private var trail: [(point: Point, at: Double)] = []
    private var ridden = 0.0
    /// Where the ride began, was paused and was resumed, and either side of
    /// a gap nobody rode.
    private var doors: [Point] = []
    private var sent: Point?

    /// One kept point of the ride, in the order they were ridden. Answers
    /// the spot to send now, or nil.
    mutating func passed(_ point: Point) -> Point? {
        if let last = trail.last?.point, Geo.metres(last, point) <= Geo.gap {
            ridden += Geo.metres(last, point)
        } else {
            // The first point since Start or a Resume, or the far side of a
            // gap: a new run, and what was waiting on the near side is let go.
            if let last = trail.last?.point { doors.append(last) }
            doors.append(point)
            trail.removeAll()
            ridden = 0
        }
        trail.append((point, ridden))

        // The newest point the rider is far enough past. It and everything
        // older leave the trail whether or not it is sent.
        let far = ridden - Geo.ends
        guard let i = trail.lastIndex(where: { $0.at <= far }) else { return nil }
        let spot = trail[i].point
        trail.removeFirst(i + 1)

        let tallinn = Geo.cities[0]
        guard point.t - spot.t <= Self.stale,
              spot.lat >= tallinn.south, spot.lat <= tallinn.north,
              spot.lng >= tallinn.west, spot.lng <= tallinn.east,
              !doors.contains(where: { Geo.metres($0, spot) < Geo.ends }),
              sent.map({ spot.t - $0.t >= Self.every && Geo.metres($0, spot) >= Self.moved }) ?? true
        else { return nil }
        sent = spot
        return spot
    }

    /// Pause, and Finish, which pauses: where the rider stopped is a door,
    /// and the points still waiting — the last 200 m — are never sent.
    mutating func stop() {
        if let last = trail.last?.point { doors.append(last) }
        trail.removeAll()
        ridden = 0
    }

    /// Send one spot. Nothing is done with the answer and nothing is tried
    /// again: the next spot is on its way.
    static func send(_ spot: Point) async {
        _ = try? await API.post("api/seen", [
            "lat": Geo.round5(spot.lat),
            "lng": Geo.round5(spot.lng),
            "at": Int(spot.t)
        ])
    }
}
