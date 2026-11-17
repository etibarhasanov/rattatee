import CoreLocation
import Foundation
import Network
import Observation

/// Every ride on this phone, and who is signed in, if anybody is.
///
/// NOBODY HAS TO SIGN IN
///
/// What the rides are collected for is their points, so the app asks for no
/// account: people ride, press Save, and that is it. A ride is sent with
/// `anon: true`, which is what lets `/api/rides` take it with no session.
/// Somebody who does sign in (Account, on My rides) gets one thing for it:
/// their rides are also listed on their account page on the website.
///
/// THE RIDE IS KEPT ON THE PHONE UNTIL THE SERVER SAYS IT HAS IT
///
/// A ride is a file under `Disk.rides` from the moment Start is pressed. It
/// is rewritten every few points and at every pause, so a killed app, a
/// crash or a flat battery costs at most the last few dozen metres, and the
/// ride comes back Paused the next time the app opens. Save marks it
/// `waiting` on disk *before* anything is sent; only the server's answer
/// moves it on, to `saved` or, for the reasons sending again cannot change,
/// to `refused`. A ride that was never answered stays `waiting` and is sent
/// again whenever there is a reason to think it might go now: the app coming
/// to the front, the network coming back, Try now.
///
/// One known gap: `/api/rides` has no request id. If the server stores a ride
/// and its answer is then lost, the phone cannot tell that from never having
/// reached it, and the next try stores it a second time. The owner chose to
/// accept that for v1; the fix is an optional field on the route, which
/// README.md describes.
@MainActor
@Observable
final class Store {
    // MARK: Who

    /// The username the site's session belongs to, or nil signed out, which
    /// is how most riders will use the app.
    var user: String?
    /// Whether the site has been asked who this is yet.
    var checked = false
    /// Which doors the site offers an app: `appGoogle` and `appApple` on
    /// `GET /api/account`. A button is drawn only where its flag is true.
    var googleOffered = false
    var appleOffered = false

    // MARK: Rides

    /// Every ride on this phone, newest first.
    private(set) var rides: [Ride] = []
    /// Where the rider said they are going, if they did: chosen in the
    /// search, drawn on the map, and gone when the ride is saved or thrown
    /// away. Kept in memory only; a ride does not need one.
    var goal: Goal?

    /// The ride whose save the Record tab is showing the outcome of.
    var shown: String?
    /// The ride being sent right now, if one is.
    private(set) var sendingId: String?

    let recorder = Recorder()

    /// Screenshots for CI: nothing is written to disk or sent.
    @ObservationIgnored var demo = false

    @ObservationIgnored private var unwritten = 0
    @ObservationIgnored private var sendingNow = false
    @ObservationIgnored private let network = NWPathMonitor()

    /// The shortest ride worth saving. The server's `MIN_METERS` (300) is
    /// what is left after its `ENDS` (200) come off both ends, so the ride
    /// itself has to be 300 + 2 × 200 — the same 700 as the website's.
    static let shortest: Double = 700
    /// The longest name — `MAX_NAME` on the server.
    static let longestName = 60
    /// A point is kept once the phone is this far from the last kept one —
    /// `STEP` in assets/ride.js.
    static let step: Double = 12
    /// A jump faster than this, in metres a second, between two kept points
    /// is the phone guessing, not a bike — `JUMP`, 60 km/h.
    static let jump: Double = 60 / 3.6
    /// Points between writes while recording: about sixty metres.
    static let writeEvery = 5

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        rides = Disk.all()
            .compactMap { try? decoder.decode(Ride.self, from: $0) }
            .sorted { $0.started > $1.started }

        // A ride that was recording when the app was killed comes back
        // paused, with the riding time it had at its last point.
        for i in rides.indices where rides[i].status == .recording {
            if let since = rides[i].since, let last = rides[i].points.last {
                rides[i].before += max(0, Int(last.t - since.timeIntervalSince1970))
            }
            rides[i].since = nil
            rides[i].status = .paused
            write(rides[i])
        }

        recorder.onPoint = { [weak self] point in self?.add(point) }

        network.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.sendWaiting() }
        }
        network.start(queue: .main)
    }

    // MARK: The ride on the Record tab

    /// The ride being recorded, paused, or waiting for Save or Throw it away.
    var current: Ride? {
        rides.first { [.recording, .paused, .finished].contains($0.status) }
    }

    private var currentIndex: Int? {
        rides.firstIndex { [.recording, .paused, .finished].contains($0.status) }
    }

    func start() {
        guard current == nil else { return }
        if !recorder.allowed {
            if !recorder.refused { recorder.ask { [weak self] in self?.start() } }
            return
        }
        // Approximate location is a fix good to a few kilometres: every one
        // would be dropped and the ride would wait for ever. The Record tab
        // says so instead.
        guard recorder.precise else { return }
        let ride = Ride(id: UUID().uuidString.lowercased(), started: Date(), status: .recording, since: Date())
        rides.insert(ride, at: 0)
        shown = nil
        write(ride)
        recorder.start()
    }

    func pause() {
        guard let i = currentIndex, rides[i].status == .recording else { return }
        recorder.stop()
        rides[i].before = rides[i].seconds()
        rides[i].since = nil
        rides[i].status = .paused
        write(rides[i])
    }

    /// Resume, and Keep riding on the too-short card.
    func resume() {
        guard let i = currentIndex, rides[i].status != .recording else { return }
        guard recorder.allowed, recorder.precise else { return }
        rides[i].since = Date()
        rides[i].status = .recording
        write(rides[i])
        recorder.start()
    }

    func finish() {
        pause()
        guard let i = currentIndex else { return }
        rides[i].status = .finished
        write(rides[i])
    }

    func throwAway() {
        guard let i = currentIndex else { return }
        recorder.stop()
        let id = rides[i].id
        rides.remove(at: i)
        goal = nil
        if !demo { Disk.remove(id) }
    }

    /// Choose somewhere to ride to, and ask the site for the way there from
    /// wherever the phone is. Asked again when the phone first says where it
    /// is, if it had not yet.
    func head(to spot: Spot) {
        goal = Goal(spot: spot)
        // Where to? opens on where the rider has been (`Recents`).
        if !demo { Recents.shared.add(spot) }
        recorder.locate()
        Task { await findWay() }
    }

    /// A tap on the map before a ride: a place Apple's map names, or
    /// anywhere at all. Nothing here asks Google or the website's search —
    /// a named place is looked for in the phone's copy of the roll first
    /// (`Venues.same`), so a café the website knows is that café under its
    /// own id; anything else is Apple's name, or a pin whose street the
    /// phone itself works out. Then it is somewhere to go, like a search row.
    func tapped(name: String?, at point: CLLocationCoordinate2D) {
        guard current == nil else { return }
        let lat = Geo.round5(point.latitude), lng = Geo.round5(point.longitude)
        if let name, !name.isEmpty {
            head(to: Venues.shared.same(as: name, at: point)
                 ?? Spot(id: "apple-\(lat)-\(lng)", name: name, detail: "", lat: lat, lng: lng, kind: .apple))
            return
        }
        let pin = Spot(id: "pin-\(lat)-\(lng)", name: L.t("pinName"), detail: "", lat: lat, lng: lng, kind: .pin)
        head(to: pin)
        Task {
            // Apple's own answer, on the phone's terms: no Google, and no
            // cost to anybody. A pin with no street is still a pin.
            let found = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lng))
            guard let mark = found?.first, self.goal?.spot.id == pin.id else { return }
            let street = [mark.thoroughfare, mark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            self.goal?.spot.detail = street.isEmpty ? (mark.name ?? "") : street
        }
    }

    func findWay() async {
        guard !demo, let goal, goal.way == .looking, let here = recorder.here else { return }
        let ways = await Search.ways(from: here, to: goal.spot.coordinate)
        // Only if it is still the place that was asked about.
        // By id: a pin's address may have arrived meanwhile.
        guard self.goal?.spot.id == goal.spot.id else { return }
        guard let first = ways.first else { self.goal?.way = .missing; return }
        self.goal?.ways = ways
        self.goal?.chosen = 0
        self.goal?.way = .found(first)
    }

    /// Go by another of the ways on offer: the card's row of them.
    func choose(way index: Int) {
        guard let goal, goal.ways.indices.contains(index) else { return }
        self.goal?.chosen = index
        self.goal?.way = .found(goal.ways[index])
    }

    /// Save: on disk as waiting first, then sent.
    func save(name: String) async {
        guard let i = currentIndex, rides[i].status == .finished else { return }
        rides[i].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestName))
        rides[i].status = .waiting
        goal = nil
        shown = rides[i].id
        write(rides[i])
        await sendWaiting()
    }

    /// One fix from the recorder: kept or not by the website's rules.
    private func add(_ point: Point) {
        guard let i = currentIndex, rides[i].status == .recording, let since = rides[i].since else { return }
        // A fix from before Start or Resume is one the phone had cached.
        guard point.t >= since.timeIntervalSince1970 - 1 else { return }
        if let last = rides[i].points.last {
            // A fix older than the last one kept is the phone catching up.
            if point.t < last.t { return }
            let d = Geo.metres(last, point)
            if d < Self.step { return }
            if d / max(1, point.t - last.t) > Self.jump { return }
        }
        rides[i].points.append(point)
        unwritten += 1
        if unwritten >= Self.writeEvery { write(rides[i]) }
    }

    /// Write the ride on screen now — the app is going to the back.
    func keepCurrent() {
        if let ride = current { write(ride) }
    }

    // MARK: My rides

    var waiting: [Ride] { rides.filter { $0.status == .waiting } }

    /// Remove a ride from this phone. Only one the server has answered for
    /// good: a waiting ride is never thrown away from the list.
    func remove(_ id: String) {
        guard let i = rides.firstIndex(where: { $0.id == id }),
              [.saved, .refused].contains(rides[i].status) else { return }
        rides.remove(at: i)
        if !demo { Disk.remove(id) }
    }

    func ride(_ id: String?) -> Ride? {
        rides.first { $0.id == id }
    }

    // MARK: Sending

    /// Send every waiting ride that can go now, one at a time. Safe to call
    /// as often as anything likes: a second call while one is running
    /// returns at once, and the running one picks up rides that started
    /// waiting meanwhile, since it looks for the next one afresh each time.
    func sendWaiting() async {
        guard !sendingNow, !demo else { return }
        sendingNow = true
        defer { sendingNow = false; sendingId = nil }

        var tried = Set<String>()
        while let next = rides.first(where: { $0.status == .waiting && !tried.contains($0.id) && canSend($0) }) {
            tried.insert(next.id)
            sendingId = next.id
            await send(next.id)
        }
        // Then any place waiting to go on a list, after the rides: a ride is
        // what the app is for.
        await ListBook.shared.sendWaiting()
    }

    private func canSend(_ ride: Ride) -> Bool {
        if let notBefore = ride.notBefore, notBefore > Date() { return false }
        return true
    }

    private func send(_ id: String) async {
        guard let ride = self.ride(id) else { return }
        let line = Geo.line(ride.points)
        var outcome = ride

        if line.count < 2 {
            // Nothing of it is inside the box the server takes rides in.
            outcome.status = .refused
            outcome.problem = "outside"
        } else {
            do {
                let data = try await API.post("api/rides", [
                    "action": "save",
                    // Lets a save with no session through; with one, the
                    // session wins and the ride is on the account.
                    "anon": true,
                    "name": ride.name,
                    "seconds": max(1, ride.seconds()),
                    "line": line
                ])
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let saved = object?["ride"] as? [String: Any]
                outcome.status = .saved
                outcome.serverId = saved?["id"] as? String
                outcome.serverMeters = saved?["meters"] as? Int
                outcome.problem = nil
                outcome.notBefore = nil
            } catch let refusal as API.Refusal {
                outcome.problem = refusal.code
                switch refusal.code {
                case "short", "fast", "malformed":
                    outcome.status = .refused
                case "often":
                    outcome.notBefore = Self.nextUTCMidnight()
                default:
                    // 503 not-ready, no-salt, anything new: try again later.
                    // That includes `signed-out` from a server that does not
                    // take `anon` yet.
                    break
                }
            } catch {
                outcome.problem = "offline"
            }
        }

        if let i = rides.firstIndex(where: { $0.id == id }) {
            rides[i] = outcome
            write(outcome)
        }
    }

    private static func nextUTCMidnight() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: today) ?? Date().addingTimeInterval(86_400)
    }

    // MARK: Disk

    private func write(_ ride: Ride) {
        unwritten = 0
        guard !demo else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(ride) { Disk.write(data, ride.id) }
    }

    /// For LaunchScript only: rides drawn on screen, never written.
    func pretend(_ rides: [Ride], shown: String? = nil) {
        demo = true
        self.rides = rides
        self.shown = shown
    }
}
