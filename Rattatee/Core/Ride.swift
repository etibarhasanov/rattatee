import CoreLocation
import Foundation

/// One fix the recorder kept: where, when, and how sure the phone was.
///
/// All four go to the server: `/api/rides` takes a point as
/// `[lat, lng, t, acc]` — `t` the seconds since the ride began — and keeps
/// the last two beside the line, in `rides.track`, for the day rides are
/// matched to streets, per street and per direction. It never shows them to
/// anybody. The time is kept here as a clock time, since that is also how
/// the riding time of a ride interrupted by a killed app is worked out.
///
/// Stored as a four-number array rather than an object, since a long ride is
/// thousands of them and is rewritten every few points.
struct Point: Codable, Equatable {
    var lat: Double
    var lng: Double
    /// Seconds since 1970.
    var t: Double
    /// Horizontal accuracy in metres.
    var acc: Double

    init(lat: Double, lng: Double, t: Double, acc: Double) {
        self.lat = lat; self.lng = lng; self.t = t; self.acc = acc
    }

    init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        lat = try row.decode(Double.self)
        lng = try row.decode(Double.self)
        t = try row.decode(Double.self)
        acc = try row.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var row = encoder.unkeyedContainer()
        try row.encode(lat); try row.encode(lng); try row.encode(t); try row.encode(acc)
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// A ride, from the moment Start is pressed until it is removed from the phone.
struct Ride: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        /// Points are coming in.
        case recording
        /// Pause was pressed, or the app was killed while recording.
        case paused
        /// Finish was pressed; the save card is waiting for Save or Throw
        /// it away.
        case finished
        /// Save was pressed and the server has not confirmed it yet. Sent
        /// again and again until it does — see `RideBook.send`.
        case waiting
        /// The server stored it; `serverId` is its id there.
        case saved
        /// The server refused it for a reason sending again cannot change
        /// (`short`, `fast`, `malformed`). Kept on the phone so it is not
        /// lost silently, and listed as Not kept.
        case refused
    }

    var id: String
    var started: Date
    var status: Status
    var name: String = ""
    var points: [Point] = []

    /// Riding time before the current stretch, in seconds.
    var before: Int = 0
    /// When the current stretch of riding began; nil while not recording.
    var since: Date?

    /// What the server answered.
    var serverId: String?
    var serverMeters: Int?
    /// The server's word for the last refusal: "often", "short", "fast",
    /// "malformed", or "offline" for no answer at all.
    var problem: String?
    /// "often" means not again before the next UTC midnight.
    var notBefore: Date?

    /// Riding time, pauses left out.
    func seconds(at now: Date = Date()) -> Int {
        before + (since.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0)
    }

    var metres: Double { Geo.length(points) }

    /// Average speed over the riding time, in km/h, once there is enough of
    /// a ride for one to mean anything.
    var average: Double? {
        let s = seconds()
        guard s >= 10, metres >= 50 else { return nil }
        return metres / 1000 / (Double(s) / 3600)
    }

    /// The fastest stretch of half a minute or more, in km/h.
    ///
    /// Not the fastest pair of points: one fix that lands thirty metres off
    /// makes a twelve-metre gap read 60 km/h for a second, and a top speed
    /// is the one number people would believe. Over thirty seconds a jump
    /// like that is averaged with everything round it. A stretch that crosses
    /// a pause is skipped, since its time includes standing still.
    var topSpeed: Double? {
        let window = 30.0
        var best = 0.0
        var j = 0
        var run = [0.0]
        for k in 1..<max(points.count, 1) { run.append(run[k - 1] + Geo.metres(points[k - 1], points[k])) }
        for i in points.indices {
            if j < i { j = i }
            while j < points.count - 1 && points[j].t - points[i].t < window { j += 1 }
            let dt = points[j].t - points[i].t
            // Longer than twice the window is a pause in the middle of it.
            guard dt >= window, dt <= window * 2 else { continue }
            best = max(best, (run[j] - run[i]) / dt * 3.6)
        }
        return best > 0 ? best : nil
    }

    /// When the ride began and ended: its first and last points.
    var span: (Date, Date)? {
        guard let first = points.first, let last = points.last else { return nil }
        return (Date(timeIntervalSince1970: first.t), Date(timeIntervalSince1970: last.t))
    }

    /// The name, or "Ride · Fri 14 Nov" when it was not given one.
    var title: String {
        name.isEmpty ? L.t("rideUntitled", ["date": L.date(started)]) : name
    }
}

/// The few sums the recorder and the upload need, the same as the website's
/// `assets/ride.js` and the server's `functions/api/rides.js`.
enum Geo {
    /// Metres between two points, on the flat-earth approximation the website
    /// uses; at a dozen metres apart in Tallinn it is exact to the centimetre.
    static func metres(_ a: Point, _ b: Point) -> Double {
        let rad = Double.pi / 180
        let x = (b.lng - a.lng) * rad * cos((a.lat + b.lat) / 2 * rad)
        let y = (b.lat - a.lat) * rad
        return (x * x + y * y).squareRoot() * 6_371_000
    }

    static func length(_ points: [Point]) -> Double {
        guard points.count > 1 else { return 0 }
        var m = 0.0
        for i in 1..<points.count { m += metres(points[i - 1], points[i]) }
        return m
    }

    static func round5(_ x: Double) -> Double { (x * 100_000).rounded() / 100_000 }

    /// The box the server accepts points in — `nearTallinn()` in the
    /// website's `functions/api/_lib.js`. A ride with one point outside it is
    /// refused whole, so points outside are left out before sending.
    static func inTallinn(_ p: Point) -> Bool {
        abs(p.lat - 59.437) <= 0.55 && abs(p.lng - 24.7536) <= 1.1
    }

    /// The most points one ride may carry — `MAX_POINTS` on the server.
    static let maxPoints = 3500

    /// The line as the server takes it: `[lat, lng, t, acc]` — five decimals,
    /// whole seconds since the first point, whole metres — inside the box, and
    /// no more than `maxPoints` of it. The server keeps the last two only if
    /// every point has them and they are sane (a `t` from 0 to a day, an
    /// accuracy up to a kilometre), which these always are short of a ride
    /// paused overnight. A longer line is thinned
    /// evenly, keeping the first and the last point; a 3,500-point ride is
    /// about forty kilometres, so this only happens on very long days, and a
    /// point every 24 m instead of every 12 still follows the streets.
    static func line(_ points: [Point]) -> [[Double]] {
        let inside = points.filter(inTallinn)
        var kept = inside
        if inside.count > maxPoints {
            let step = Double(inside.count - 1) / Double(maxPoints - 1)
            kept = (0..<maxPoints).map { inside[Int((Double($0) * step).rounded())] }
        }
        // Counted from the first point kept, as the website's recorder counts.
        let zero = points.first?.t ?? 0
        return kept.map {
            [round5($0.lat), round5($0.lng), max(0, ($0.t - zero).rounded()), $0.acc.rounded()]
        }
    }
}
