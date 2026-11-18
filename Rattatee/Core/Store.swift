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
    /// The voice that says the turns of the way to `goal`.
    let guide = Guide()
    /// The radio on a ride, which goes under that voice.
    let radio = Radio()

    /// Screenshots for CI: nothing is written to disk or sent.
    @ObservationIgnored var demo = false

    @ObservationIgnored private var unwritten = 0
    @ObservationIgnored private var sendingNow = false
    /// Finish is asking the phone what was not ridden: a second press waits.
    @ObservationIgnored private var finishing = false
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
            // The pause began where the points stopped, not when the app
            // opened again.
            rides[i].pausedAt = rides[i].points.last?.t ?? Date().timeIntervalSince1970
            rides[i].since = nil
            rides[i].status = .paused
            write(rides[i])
        }

        recorder.onPoint = { [weak self] point in self?.add(point) }
        guide.radio = radio
        radio.guide = guide

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
        // The radio first, if it was on last ride, so the greeting finds it
        // on and is said over it: a stream takes a second or two to come,
        // which is the greeting's, and then the music comes up under it.
        radio.begin()
        // A new ride only: `resume()` does not greet.
        guide.greet()
        recorder.start()
        // Motion & Fitness is asked here, the first time, rather than at
        // Finish: `Motion` says why it is wanted at all.
        Motion.askOnce()
    }

    func pause() {
        guard let i = currentIndex, rides[i].status == .recording else { return }
        recorder.stop()
        rides[i].before = rides[i].seconds()
        rides[i].since = nil
        rides[i].pausedAt = Date().timeIntervalSince1970
        rides[i].status = .paused
        write(rides[i])
    }

    /// Resume, and Keep riding on the too-short card.
    func resume() {
        guard let i = currentIndex, rides[i].status != .recording else { return }
        guard recorder.allowed, recorder.precise else { return }
        let now = Date()
        if let from = rides[i].pausedAt {
            rides[i].breaks = (rides[i].breaks ?? []) + [[from, now.timeIntervalSince1970]]
        }
        rides[i].pausedAt = nil
        // Riding again: Finish works the active time out afresh.
        rides[i].active = nil
        rides[i].since = now
        rides[i].status = .recording
        write(rides[i])
        recorder.start()
        // Keep riding, after a Finish that stopped it.
        radio.begin()
    }

    /// Pause, ask the phone which stretches were walked or driven, leave
    /// them out, and only then show the save card — the question takes a
    /// moment, and the card should not show numbers that are about to change.
    /// With nothing to ask, nothing is set aside and the active time is the
    /// riding time.
    func finish() {
        pause()
        radio.halt()
        guard let i = currentIndex, rides[i].status == .paused, !finishing else { return }
        finishing = true
        let id = rides[i].id, started = rides[i].started
        Task {
            var found: [Motion.Stretch] = []
            if !demo { found = await Motion.stretches(from: started, to: Date()) }
            finishing = false
            guard let j = rides.firstIndex(where: { $0.id == id }), rides[j].status == .paused else { return }
            rides[j].leaveOut(Motion.notRidden(found, by: rides[j].points))
            rides[j].status = .finished
            write(rides[j])
        }
    }

    func throwAway() {
        guard let i = currentIndex else { return }
        recorder.stop()
        radio.halt()
        let id = rides[i].id
        rides.remove(at: i)
        goal = nil
        guide.forget()
        if !demo { Disk.remove(id) }
    }

    /// Choose somewhere to ride to, and ask the site for the way there from
    /// wherever the phone is. Asked again when the phone first says where it
    /// is, if it had not yet.
    func head(to spot: Spot) {
        goal = Goal(spot: spot)
        // Where to? opens on where the rider has been (`Recents`).
        if !demo { Recents.shared.add(spot) }
        guide.forget()
        recorder.locate()
        Task { await findWay() }
    }

    /// A tap on the map before a ride, or during one: a place Apple's map
    /// names, or anywhere at all. Nothing here asks Google or the website's search —
    /// a named place is looked for in the phone's copy of the roll first
    /// (`Venues.same`), so a café the website knows is that café under its
    /// own id; anything else is Apple's name, or a pin whose street the
    /// phone itself works out. Then it is somewhere to go, like a search row.
    func tapped(name: String?, at point: CLLocationCoordinate2D) {
        // Before a ride, or while one is being ridden — never on the save
        // card, where somewhere to go would outlive the ride it was for.
        if let current, ![.recording, .paused].contains(current.status) { return }
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
        // Chosen mid-ride, the way sets off the way the rider is already
        // going, as a new way off the old one does (`reroute`): nil before
        // a ride, when there is no line to take a heading from.
        let riding = current.map { [.recording, .paused].contains($0.status) } ?? false
        let heading = riding ? Geo.heading(current?.points ?? []) : nil
        let ways = await Search.ways(from: here, to: goal.spot.coordinate, heading: heading)
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
        guide.forget()
    }

    // MARK: Off the way

    /// Points in a row further than `Way.astray` from the line before it is
    /// said: one is the phone's fix wandering, two is the rider.
    static let astrayPoints = 2
    /// Ridden backwards along the way this far, and it is said.
    static let backSoon: Double = 40
    /// Really going wrong, and a new way is asked for: this far from the
    /// way, this far ridden backwards along it, or this far ridden at all
    /// since it was said and the rider still not back.
    static let farOff: Double = 150
    static let farBack: Double = 150
    static let lostFor: Double = 250
    /// Not asked again sooner than this after it answered nothing, so a
    /// tunnel or a dead signal is not a request every point.
    static let rerouteEvery: TimeInterval = 30

    /// One kept point of a ride with somewhere to go: on the way, the turns
    /// are said as before; off it or going backwards along it, the row says
    /// so, once, and a new way is asked for when the rider is plainly not
    /// coming back to it.
    private func follow(_ point: Point, after before: Point?, on way: Way, ridden: Double) {
        guard var goal = self.goal, goal.lost?.finding != true else { return }
        let spot = way.place(of: point.coordinate)
        let off = spot.off > Way.astray

        // Backwards is the way's own distance going down from point to
        // point. Only where that change is about the distance between the
        // two points: a way that passes near itself can make the nearest
        // spot leap to another part of it, which is not the rider turning.
        if !off {
            let step = before.map { Geo.metres($0, point) } ?? 0
            let change = spot.along - goal.along
            if abs(change) <= step * 1.5 + 10 {
                if change < 0 { goal.back -= change } else if change > 5 { goal.back = 0 }
            }
            goal.along = spot.along
        }
        goal.astray = off ? goal.astray + 1 : 0
        // Once it has been said, one point off is enough to keep saying it.
        let surelyOff = off && (goal.astray >= Self.astrayPoints || goal.lost != nil)
        let back = !off && goal.back >= Self.backSoon

        if !surelyOff && !back {
            // On the way, or not yet surely off it.
            goal.lost = nil
            self.goal = goal
            if !off { guide.hear(point.coordinate, on: way) }
            return
        }

        let kind: Lost.Kind = off ? .off : .back
        if goal.lost == nil || goal.lost?.kind != kind {
            goal.lost = Lost(kind: kind, since: goal.lost?.since ?? ridden, metres: spot.off,
                             failed: goal.lost?.failed)
            guide.warn(kind)
        }
        goal.lost?.metres = spot.off

        if let lost = goal.lost, !demo {
            let wrong = off ? spot.off >= Self.farOff : goal.back >= Self.farBack
            let long = ridden - lost.since >= Self.lostFor
            let waited = lost.failed.map { Date().timeIntervalSince($0) >= Self.rerouteEvery } ?? true
            if (wrong || long) && waited {
                // Marked before the question goes, so the points that arrive
                // while it is out do not ask it again.
                goal.lost?.finding = true
                let here = point.coordinate
                let heading = Geo.heading(current?.points ?? [])
                Task { await reroute(from: here, heading: heading) }
            }
        }
        self.goal = goal
    }

    /// A new way to the same place, from where the rider is now and setting
    /// off the way they are going: somebody who has ridden this far past
    /// "Going the wrong way" means it, and a new way that began "Turn
    /// around" would only say it again. It takes the place of the old one,
    /// turns and all, and the voice starts over on it; with no answer, the
    /// old one stays and it is asked again later.
    private func reroute(from here: CLLocationCoordinate2D, heading: Int?) async {
        guard let goal else { return }
        let ways = await Search.ways(from: here, to: goal.spot.coordinate, heading: heading)
        guard self.goal?.spot.id == goal.spot.id else { return }
        guard let first = ways.first else {
            self.goal?.lost?.finding = false
            self.goal?.lost?.failed = Date()
            return
        }
        self.goal?.ways = ways
        self.goal?.chosen = 0
        self.goal?.way = .found(first)
        self.goal?.lost = nil
        self.goal?.along = 0
        self.goal?.back = 0
        self.goal?.astray = 0
        guide.forget()
    }

    /// Save: on disk as waiting first, then sent.
    func save(name: String) async {
        guard let i = currentIndex, rides[i].status == .finished else { return }
        rides[i].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestName))
        rides[i].status = .waiting
        goal = nil
        guide.forget()
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
            // Too fast for a bike is a train, a bus or a car — or the
            // phone guessing. Not riding either way, but carried rather
            // than dropped: Finish tells the two apart (`Timeline.runs`).
            if d / max(1, point.t - last.t) > Self.jump { carry(point, in: i); return }
        }
        // On the train of a way by train, the phone is moving and the bike
        // is not being ridden: a point kept there would save the railway as
        // a bike route, and the website's doors would read it as a shortcut
        // across the tracks. So none is kept as riding: it is carried, the
        // ride goes on from the far station, and the ride's page shows the
        // train as a train.
        if case .found(let way) = goal?.way, let train = way.train {
            let spot = way.place(of: point.coordinate)
            if spot.off <= Way.astray && train.rail.contains(spot.along) { carry(point, in: i); return }
        }
        let before = rides[i].points.last
        rides[i].points.append(point)
        if case .found(let way) = goal?.way {
            follow(point, after: before, on: way, ridden: rides[i].metres)
        }
        unwritten += 1
        if unwritten >= Self.writeEvery { write(rides[i]) }
    }

    /// Keep a point that is not riding — `Ride.carried` — once it is
    /// `Timeline.carriedStep` from the last one carried.
    private func carry(_ point: Point, in i: Int) {
        if let last = rides[i].carried?.last {
            if point.t <= last.t || Geo.metres(last, point) < Timeline.carriedStep { return }
        }
        rides[i].carried = (rides[i].carried ?? []) + [point]
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
                    // The active time: what the server shares out between
                    // the pieces and judges the speed over.
                    "seconds": max(1, ride.ridden()),
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
        radio.demo = true
        self.rides = rides
        self.shown = shown
    }
}
