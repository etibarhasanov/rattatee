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
/// And how high it was. Since 2026-11-18 a fix's altitude above the sea is
/// kept too, and sent as a fifth number — `[lat, lng, t, acc, alt]` — which
/// the server keeps in `rides.track` beside the time and the accuracy, so a
/// ride can one day say where it climbed, which a line on a flat map cannot.
/// It is the GPS height Core Location gives with the fix, good to ten or
/// twenty metres a point: a climb is a trend across many points, never the
/// step between two. A fix with no valid height has none, and is sent as
/// four numbers; the server then keeps no heights for that ride at all,
/// rather than heights that do not line up.
///
/// Stored as a four- or five-number array rather than an object, since a long
/// ride is thousands of them and is rewritten every few points. A ride
/// recorded before heights were kept reads back with none.
struct Point: Codable, Equatable {
    var lat: Double
    var lng: Double
    /// Seconds since 1970.
    var t: Double
    /// Horizontal accuracy in metres.
    var acc: Double
    /// Altitude above mean sea level in metres, or nil where the fix had none.
    var alt: Double?

    init(lat: Double, lng: Double, t: Double, acc: Double, alt: Double? = nil) {
        self.lat = lat; self.lng = lng; self.t = t; self.acc = acc; self.alt = alt
    }

    init(from decoder: Decoder) throws {
        var row = try decoder.unkeyedContainer()
        lat = try row.decode(Double.self)
        lng = try row.decode(Double.self)
        t = try row.decode(Double.self)
        acc = try row.decode(Double.self)
        alt = try row.isAtEnd ? nil : row.decodeIfPresent(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var row = encoder.unkeyedContainer()
        try row.encode(lat); try row.encode(lng); try row.encode(t); try row.encode(acc)
        if let alt { try row.encode(alt) }
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
        /// The server answered. Signed in, it stored the ride and
        /// `serverId` is its id there. With nobody signed in it counted
        /// the streets the ride went down and kept nothing — `phoneOnly`
        /// — so there is no id, and the ride is this file and no more.
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

    /// When Pause was last pressed, in seconds since 1970; nil while riding.
    var pausedAt: Double?
    /// Every pause that was resumed from, as `[from, to]` in seconds since
    /// 1970: the time in them is not riding, so a walk during one is not
    /// taken off the active time twice. Optional, since rides recorded
    /// before it was written have none.
    var breaks: [[Double]]?

    /// Riding time with the stretches the phone was walked or driven taken
    /// off — `Motion` — worked out at Finish; nil before that, and for a ride
    /// the phone could not ask about. It is what is sent as the ride's
    /// seconds and what the average is taken over.
    var active: Int?
    /// The points Finish found were walked or driven, a stretch each. Kept
    /// on the phone and drawn on the map, dotted, so the rider sees the
    /// whole of where they went — but not riding: never in `points`, never
    /// in the distance, the times or the speeds, and never sent.
    var aside: [[Point]]?

    /// What each stretch of `aside` was, pair for pair: "walk" or
    /// "vehicle". Optional and possibly shorter, since rides finished
    /// before it was written have none; a stretch with no word is read as a
    /// walk, which most were.
    var asideKinds: [String]?
    /// Points the recorder would not keep as riding while the ride was
    /// recorded: too fast for a bike, or on the rails of a way by train.
    /// They used to be dropped, and a train was then nothing at all on the
    /// ride. Finish gathers them into the journeys they were and moves those
    /// to `aside`, as vehicle — `Timeline`. Never sent.
    var carried: [Point]?

    /// What the stretch at `k` of `aside` was.
    func asideKind(_ k: Int) -> Part.Kind {
        guard let kinds = asideKinds, kinds.indices.contains(k) else { return .walk }
        return kinds[k] == "vehicle" ? .vehicle : .walk
    }

    /// Add a stretch to `aside` with its word, keeping the two in step
    /// where the ride has stretches from before there were words.
    private mutating func setAside(_ stretch: [Point], as kind: String) {
        let have = aside ?? []
        var kinds = asideKinds ?? []
        while kinds.count < have.count { kinds.append("walk") }
        aside = have + [stretch]
        asideKinds = kinds + [kind]
    }

    /// How far the stretches set aside go.
    var leftOut: Double {
        (aside ?? []).reduce(0) { $0 + Geo.length($1) }
    }

    /// Save was pressed with nobody signed in, so what the save card
    /// said holds whatever happens next: the ride stays on this phone and
    /// the website counts it without keeping it. It is sent with no
    /// session even if somebody signs in before it has gone. Nil for a
    /// ride saved before this was written, which is sent as it always was.
    var phoneOnly: Bool?

    /// What the server answered, for a ride it kept: nothing, for one it
    /// only counted.
    var serverId: String?
    var serverMeters: Int?
    /// The server's word for the last refusal: "often", "short", "fast",
    /// "malformed", or "offline" for no answer at all.
    var problem: String?
    /// "often" means not again before the next UTC midnight; any other
    /// failure means not again before a wait that doubles with `tries`.
    var notBefore: Date?
    /// Sends that failed in a row for a reason sending again might change —
    /// no answer, or a refusal that is not final. Nil once saved, and on a
    /// ride from before this field, which decodes the same.
    var tries: Int?

    /// Riding time, pauses left out.
    func seconds(at now: Date = Date()) -> Int {
        before + (since.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0)
    }

    var metres: Double { Geo.length(points) }

    /// The active time where Finish found one, else the riding time.
    func ridden(at now: Date = Date()) -> Int {
        active ?? seconds(at: now)
    }

    /// Whether Finish took anything off: the save card then shows active
    /// and total time apart.
    var trimmed: Bool {
        guard let active else { return false }
        return active < seconds() || !(aside ?? []).isEmpty
    }

    /// Set aside what was not riding, and work out the active time. Three
    /// things, in this order:
    ///
    /// - the stretches the phone said were walked or driven go to `aside`,
    ///   each with its word;
    /// - the points the recorder carried rather than kept — a train — go
    ///   there too, as the journeys they were (`Timeline.runs`);
    /// - and the wandering of a stop is taken out of the points, leaving
    ///   where the rider arrived and where they left (`Timeline.settled`).
    ///
    /// The active time is the riding time less all of that: the stretches
    /// set aside, and every stop — a leg that stood for `Timeline.stopShortest`
    /// or more. A wait at a crossing stays in it, as it always has. Counted
    /// once where two overlap, and less any part that fell in a pause, which
    /// was not riding time anyway.
    ///
    /// Asked again after Keep riding, over the whole ride; a stretch whose
    /// points are already gone takes nothing more off, and the stretches
    /// already in `aside` are counted from their own first and last points.
    mutating func leaveOut(_ stretches: [Motion.Stretch], at now: Date = Date()) {
        let start = started.timeIntervalSince1970
        let end = pausedAt ?? now.timeIntervalSince1970
        for s in stretches {
            let inside = points.filter { $0.t >= s.from && $0.t <= s.to }
            guard !inside.isEmpty else { continue }
            setAside(inside, as: s.driven ? "vehicle" : "walk")
            points.removeAll { $0.t >= s.from && $0.t <= s.to }
        }
        for run in Timeline.runs(carried ?? []) { setAside(run, as: "vehicle") }
        carried = nil
        points = Timeline.settled(points)

        var away: [(Double, Double)] = stretches.map { ($0.from, $0.to) }
        for stretch in aside ?? [] {
            if let first = stretch.first, let last = stretch.last { away.append((first.t, last.t)) }
        }
        for i in points.indices.dropFirst() {
            let a = points[i - 1], b = points[i]
            if b.t - a.t >= Timeline.stopShortest && Timeline.still(a, b) { away.append((a.t, b.t)) }
        }
        let gone = Timeline.covered(away, from: start, to: end, less: breaks ?? [])
        active = max(0, seconds(at: now) - Int(gone.rounded()))
    }

    /// Average speed over the active time, in km/h, once there is enough of
    /// a ride for one to mean anything.
    var average: Double? {
        let s = ridden()
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

    /// The way a line is going at its end, in whole degrees from north:
    /// from the last point at least `over` metres behind its end to the
    /// end, so one fix wandering sideways does not turn it. Nil for a line
    /// that has not gone that far yet.
    static func heading(_ points: [Point], over: Double = 30) -> Int? {
        guard let end = points.last, let from = points.last(where: { metres($0, end) >= over }) else { return nil }
        let rad = Double.pi / 180
        let east = (end.lng - from.lng) * cos((from.lat + end.lat) / 2 * rad)
        let north = end.lat - from.lat
        return (Int((atan2(east, north) / rad).rounded()) + 360) % 360
    }

    /// Two points further apart than this are a gap, not a step: the server
    /// cuts the line there and keeps each side as a ride of its own — `GAP`
    /// in the website's `functions/api/_sections.js`. A gap is where a walk,
    /// a train or a lost signal was left out, and it was not ridden, so it is
    /// not counted in a ride's length either.
    static let gap: Double = 250

    static func length(_ points: [Point]) -> Double {
        guard points.count > 1 else { return 0 }
        var m = 0.0
        for i in 1..<points.count {
            let d = metres(points[i - 1], points[i])
            if d <= gap { m += d }
        }
        return m
    }

    /// The ridden line in the pieces it is drawn in: cut where two points
    /// are a gap apart, and where a stretch set aside fell between them, so
    /// a walk is a dotted line on the map and never a straight solid one
    /// across it.
    static func runs(_ points: [Point], around aside: [[Point]]) -> [[Point]] {
        var runs: [[Point]] = []
        var run: [Point] = []
        for p in points {
            if let last = run.last,
               metres(last, p) > gap || aside.contains(where: { s in s.contains { $0.t > last.t && $0.t < p.t } }) {
                runs.append(run)
                run = []
            }
            run.append(p)
        }
        if !run.isEmpty { runs.append(run) }
        return runs
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
    /// whole seconds since the first point, whole metres — and `alt` after
    /// them in whole metres where the fix had a height, inside the box, and
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
            let row = [round5($0.lat), round5($0.lng), max(0, ($0.t - zero).rounded()), $0.acc.rounded()]
            return $0.alt.map { row + [$0.rounded()] } ?? row
        }
    }
}
