import CoreLocation
import Foundation
import Network
import Observation

/// Every ride on this phone, and who is signed in, if anybody is.
///
/// NOBODY HAS TO SIGN IN, AND THEN THE RIDE IS THEIRS ALONE
///
/// The app asks for no account: people ride, press Save, and that is it. A
/// ride is sent with `anon: true`, which is what lets `/api/rides` take it
/// with no session, and since 2026-11-20 the website does not keep such a
/// ride: it counts the streets the ride went down, into what it knows of
/// how each street rides, and lets the ride go. The ride is the file on
/// this phone and nothing else, and the save card says so before Save is
/// pressed. So a ride saved with nobody signed in is marked `phoneOnly` and
/// sent with no session even if somebody signs in before it has gone:
/// what the card said is what happens. Nothing afterwards offers to move
/// such a ride to an account, and nothing on the phone tells it from a
/// kept one. The owner's line was that neither is needed.
///
/// Somebody who does sign in (Account, on My rides) has their rides kept on
/// the website under the account and drawn on the ride's page here. Since 2026-11-22 every save carries the
/// ride in a few numbers as well (`Ride.summary`), which the account adds
/// up — a ride outside the four cities included, sent for those alone
/// (`send`) — and My rides shows (`AccountTotals`). With nobody
/// signed in the website ignores them and nothing more is kept.
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
/// One known gap. A ride whose answer was lost on the way back looks, from
/// here, exactly like one that never arrived, and is sent again — and the
/// website does it again: counted a second time with nobody signed in,
/// kept as a second ride with somebody. For an hour on 2026-11-20 every
/// save carried `request`, the ride's own id, for the website to know a
/// repeat by. The owner took it out the same day: a small chance and a
/// small harm, and not worth the website remembering an id for every ride
/// it says it keeps nothing of.
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
    /// When the phone last measured itself going faster than any bike, for
    /// `carriedFixes` fixes running (`moving`). Less than `carriedFor` ago,
    /// the rider is on a train or in a car, and the way waits — CARRIED,
    /// NOT RIDDEN, below.
    private(set) var carriedAt: Date?
    @ObservationIgnored private var fastFixes = 0

    var carried: Bool {
        carriedAt.map { Date().timeIntervalSince($0) < Self.carriedFor } ?? false
    }

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
    /// A point is kept once the phone is this far from the last kept one.
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
        recorder.onUnsure = { [weak self] fix in self?.unsure(fix) }
        recorder.onSpeed = { [weak self] slowest in self?.moving(slowest) }
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
        carriedAt = nil
        fastFixes = 0
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
        // Chosen on a train: the way the train is going is not the rider's.
        goal?.alighted = carried
        // Where to? opens on where the rider has been (`Recents`).
        if !demo { Recents.shared.add(spot) }
        guide.forget()
        recorder.locate()
        Task { await findWay() }
    }

    /// A touch on the map before a ride, or during one: a tap on a place
    /// Apple's map names, which comes with its name, or a hold anywhere at
    /// all, which comes with none. Nothing here asks Google or the website's
    /// search — a named place is looked for in the phone's copy of the roll
    /// first (`Venues.same`), so a café the website knows is that café under
    /// its own id; anything else is Apple's name, or a pin whose street the
    /// phone itself works out. Then it is somewhere to go, like a search row.
    func touched(name: String?, at point: CLLocationCoordinate2D) {
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
        // Chosen while going, the way sets off the way the rider is going,
        // as a new way off the old one does (`reroute`). Standing still,
        // paused or before a ride it is asked with no heading — STANDING,
        // NOT GOING, below.
        let heading = Self.going(current, carried: carried) ? Geo.heading(current?.points ?? []) : nil
        let ways = await Search.ways(from: here, to: goal.spot.coordinate, heading: heading)
        // Only if it is still the place that was asked about.
        // By id: a pin's address may have arrived meanwhile.
        guard self.goal?.spot.id == goal.spot.id else { return }
        guard let first = ways.first else { self.goal?.way = .missing; return }
        self.goal?.ways = ways
        self.goal?.chosen = 0
        self.goal?.way = .found(first)
    }

    /// Go by another of the ways on offer: the card's row of them before a
    /// ride, or the same row under the numbers after a new way mid-ride,
    /// where a press is the rider choosing and the choice is over. A tap on
    /// a way's faint line on the map is the same press.
    func choose(way index: Int) {
        guard var goal, goal.ways.indices.contains(index) else { return }
        take(index, in: &goal)
        endPicking(&goal)
        self.goal = goal
    }

    /// Make one of the ways on offer the way: followed from wherever the
    /// rider is on it, and its turns said from the start.
    private func take(_ index: Int, in goal: inout Goal) {
        goal.chosen = index
        goal.way = .found(goal.ways[index])
        goal.lost = nil
        goal.along = 0
        goal.back = 0
        goal.astray = 0
        goal.adrift = 0
        goal.railAlong = nil
        goal.atStation = false
        guide.forget()
    }

    private func endPicking(_ goal: inout Goal) {
        goal.picking = nil
        goal.aloneOn = nil
        goal.alonePoints = 0
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
    /// Or this long ridden since it was said, in seconds, and the rider
    /// still not back — `Lost.seconds`, which leaves out a leg spent
    /// standing. The owner's word on 2026-11-25: somebody riding somewhere
    /// else for more than thirty seconds is not at a shop and not cutting a
    /// corner, it is ongoing, so just find the new way and go. Until then a
    /// rider who stayed between `Way.astray` and `farOff` of the way was
    /// told they were off it and then left with the old way for 250 m —
    /// most of a minute at a bike's pace, and nearer a minute and a half on
    /// a path. At thirty kilometres an hour and faster `lostFor` still
    /// comes first.
    ///
    /// WHAT IT ASKS, IN REQUESTS A RIDDEN HOUR
    ///
    /// One request each time, the website's question with a `heading`: the
    /// router's own way, no row read for it, and two rows by key for a
    /// rider who is signed in. By this rule it cannot be asked sooner than
    /// thirty seconds of riding after it was said, and it is said two
    /// points off a way that set off the way the rider was going, so under
    /// 120 a ridden hour from somebody who never once rides the way they
    /// are given — nearer 70 at 18 km/h, a street over from every way,
    /// where the 250 m it comes before made 50. That is the worst of it and
    /// not the ride: an ordinary ride gains one request for each time its
    /// rider left the way for longer than half a minute and would have been
    /// back on it within 250 m. `farOff` and `farBack` are as they were.
    static let lostSeconds: TimeInterval = 30
    /// Not asked again sooner than this after it was last asked, whatever
    /// came back, so a tunnel or a dead signal is not a request every
    /// point — and neither is a bus or a slow train whose points are kept
    /// as riding, which leaves each new way within seconds of getting it.
    /// Until 2026-11-24 it held only after an answer of nothing. A hundred
    /// and twenty requests a ridden hour at the very worst, from somebody
    /// who never once rides the way they are given.
    static let rerouteEvery: TimeInterval = 30
    /// Faster than this, as the phone measures itself, is not a bike: a
    /// train, a bus or a car. 40 km/h, which a bike in Tallinn sees only
    /// downhill, and an Elron train between two stations is well past.
    static let carriedSpeed: Double = 40 / 3.6
    /// Fixes in a row that fast before it counts, a second or so apart, so
    /// one fix the satellites got wrong is not a train.
    static let carriedFixes = 3
    /// And for how long after the last of them the rider is still carried:
    /// a train standing at a station is still a train. Two minutes covers
    /// the slowing, the doors and the setting off again, and after the last
    /// station the walk off the platform.
    static let carriedFor: TimeInterval = 120
    /// The widest circle a fix may have and still say where along the rail
    /// of a way by train the train is: wider, and the kilometres the row
    /// counts down would jump about by as much.
    static let railSure: Double = 300
    /// The station of a way by train is this near, as the crow flies, and
    /// the rider is at it (`platform`); and this far, and they have left it.
    static let stationNear: Double = 250
    static let stationLeft: Double = 500
    /// Carried this far down the rail, and the train has left with the
    /// rider on it.
    static let boardedAfter: Double = 300
    /// And this long after the train was to leave, a rider still at the
    /// station has missed it, and the way is followed again.
    static let missedAfter: TimeInterval = 300
    /// After a new way, how far the rider may ride before its others stop
    /// being a choice and the first is simply the way. By then the ways
    /// have long parted, or are so nearly one that it makes no difference.
    static let pickFor: Double = 800

    /// One kept point of a ride with somewhere to go: on the way, the turns
    /// are said as before; off it or going backwards along it, the row says
    /// so, once, and a new way is asked for when the rider is plainly not
    /// coming back to it. Just after a new way with others, `pick` has the
    /// point first.
    private func follow(_ point: Point, after before: Point?, ridden: Double) {
        guard var goal = self.goal, goal.lost?.finding != true else { return }
        // A point kept knows better than the fixes that were not (`note`),
        // and is not on a train.
        goal.adrift = 0
        goal.railAlong = nil
        if pick(point, in: &goal, ridden: ridden) { self.goal = goal; return }
        // Read after `pick`, which may have made another of the ways the way.
        guard case .found(let way) = goal.way else { return }
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
            goal.alighted = false
            self.goal = goal
            if !off { guide.hear(point.coordinate, on: way) }
            return
        }

        let kind: Lost.Kind = off ? .off : .back
        // How long it has gone on since it was said, counted in riding: the
        // leg to this point, unless it was spent standing. Nothing to add
        // to at the point it is first said.
        if let before, !Timeline.still(before, point) { goal.lost?.seconds += point.t - before.t }
        if goal.lost == nil || goal.lost?.kind != kind {
            goal.lost = Lost(kind: kind, since: goal.lost?.since ?? ridden, seconds: goal.lost?.seconds ?? 0,
                             metres: spot.off, failed: goal.lost?.failed)
            guide.warn(kind)
        }
        goal.lost?.metres = spot.off

        if let lost = goal.lost, !demo {
            let wrong = off ? spot.off >= Self.farOff : goal.back >= Self.farBack
            let long = ridden - lost.since >= Self.lostFor || lost.seconds >= Self.lostSeconds
            let waited = goal.asked.map { Date().timeIntervalSince($0) >= Self.rerouteEvery } ?? true
            if (wrong || long) && waited {
                // Marked before the question goes, so the points that arrive
                // while it is out do not ask it again.
                goal.lost?.finding = true
                goal.asked = Date()
                let here = point.coordinate
                // Just off a train, the way it was going says nothing.
                let heading = goal.alighted ? nil : Geo.heading(current?.points ?? [])
                goal.alighted = false
                Task { await reroute(from: here, heading: heading) }
            }
        }
        self.goal = goal
    }

    // MARK: Standing, not going

    /// STANDING, NOT GOING
    ///
    /// A way asked with a `heading` is the router's, set off that way, and
    /// the website reads no rides for it: it cannot be the way people ride,
    /// and none of its buttons is ever *Ridden*. That is right for a new way
    /// off the old one, asked of a rider going somewhere. Until 2026-11-27
    /// it was also how a place picked in the search was asked for whenever
    /// a ride was recording or paused, so a rider who stopped, took the
    /// phone out and picked where to go was given the router's ways and
    /// never the way they and others ride: the owner, standing at Magasini
    /// with a ride running, was offered three ways to Balti jaam and none up
    /// Kentmanni, which was ridden five to seven times that way.
    ///
    /// So the heading goes only with a rider going: a ride recording, not
    /// carried, whose last point was kept less than `stillFor` ago. A point
    /// is kept every `step` metres, every few seconds at any pace a bike
    /// keeps, so a rider who has kept none for that long is standing. It
    /// asks nothing more often: one request for each place picked, as
    /// before, which is now the website's dearer question — BRouter's ways
    /// and up to six hundred keys of rides — where it was the cheaper one.

    /// A rider who has kept no point for this long is standing. Twenty
    /// seconds is two `step`s at walking pace, ten at an easy ride's.
    static let stillFor: TimeInterval = 20

    /// Whether the rider of `ride` is going somewhere — STANDING, NOT GOING.
    static func going(_ ride: Ride?, carried: Bool, at now: Date = Date()) -> Bool {
        guard let ride, ride.status == .recording, !carried, let last = ride.points.last else { return false }
        return now.timeIntervalSince1970 - last.t < stillFor
    }

    // MARK: Carried, not ridden

    /// CARRIED, NOT RIDDEN
    ///
    /// A train, a bus or a car with the bike in it is not riding, and a way
    /// by bike cannot be followed from one. Until 2026-11-25 the app could
    /// not tell. A train going under 60 km/h between two fixes was riding to
    /// it, so `follow` judged every point: off the way, a new way asked from
    /// the moving train, its first turn shown and said, the train past it
    /// and off that way too — a new way every 150 m and a left or a right
    /// with each, which is what the owner reported from a train. And where
    /// the carriage gave no fix good enough to keep, the opposite: on
    /// 2026-11-24 the last point was on the platform at Balti jaam, a
    /// hundred metres from the way, and the row said "You're off the way ·
    /// 100 m from it" for the whole train.
    ///
    /// So the phone's own speed is listened to (`Recorder.onSpeed`). It
    /// measures it from the satellites, fix by fix, far better than two
    /// positions can; `carriedFixes` fixes in a row faster than any bike
    /// (`carriedSpeed`) and the rider is carried, until `carriedFor` after
    /// the last. While carried the way waits. No point is followed, no turn
    /// is shown or said — but a way by train's own row, which says where to
    /// get off — and nothing is asked of the website. The row says only how
    /// far from the way the phone is, once that is plainly far (`note`),
    /// and the line over it how far from the place, from where the phone
    /// is. Riding again, the first point kept is followed as any is, and
    /// off the way a new way is asked from there, once, with no heading:
    /// the way the train went says nothing of the way the rider will
    /// (`Goal.alighted`).
    ///
    /// Where the phone gives no speed — inside a carriage it may know where
    /// it is only to a kilometre — nothing is kept to follow either, and
    /// the fixes it does give move the row (`unsure`). A new way then waits
    /// for the first point ridden after it, as above.
    ///
    /// What is recorded does not change: a slow train is still kept as
    /// riding, and Finish still sets apart only what was too fast or what
    /// the coprocessor says was driven.

    /// The phone's own speed, from `Recorder.onSpeed`: the slowest a fix
    /// could have been going, in metres a second.
    private func moving(_ slowest: Double) {
        guard !demo, let i = currentIndex, rides[i].status == .recording else { return }
        guard slowest >= Self.carriedSpeed else { fastFixes = 0; return }
        fastFixes += 1
        guard fastFixes >= Self.carriedFixes else { return }
        if !carried, var goal = self.goal {
            // On board: what the row said of the platform is not true of
            // the train, and whatever comes next starts from nothing.
            if goal.lost?.finding != true { goal.lost = nil }
            goal.astray = 0
            goal.adrift = 0
            goal.back = 0
            goal.alighted = true
            goal.atStation = false
            self.goal = goal
        }
        carriedAt = Date()
    }

    /// A fix too unsure to be a point of the ride, from `Recorder.onUnsure`.
    ///
    /// The train of a way by train is not weighed by it until the rail is
    /// behind: the rail is the way, and a fix a kilometre wrong, twice,
    /// would say the rider sitting on it was off it. Where its circle takes
    /// in the rail, and is no wider than `railSure`, it says where along the
    /// rail the train is, for the row (`Goal.railAlong`).
    private func unsure(_ fix: Point) {
        guard !demo, let i = currentIndex, rides[i].status == .recording, let since = rides[i].since,
              fix.t >= since.timeIntervalSince1970 - 1 else { return }
        if let goal, case .found(let way) = goal.way, let train = way.train,
           goal.along <= train.rail.upperBound {
            let spot = way.place(of: fix.coordinate)
            if fix.acc <= Self.railSure, spot.off <= fix.acc + Way.astray, train.rail.contains(spot.along) {
                onRail(spot.along, of: way)
            }
            return
        }
        note(fix)
    }

    /// The train of a way by train is `along` its rail: what the row counts
    /// down to the station to get off at, the end of waiting at the first
    /// one once the train has carried the rider off, and "Get off at" said
    /// before the last (`Guide.alight`).
    private func onRail(_ along: Double, of way: Way) {
        guard var goal, let train = way.train else { return }
        goal.railAlong = along
        if along - train.rail.lowerBound >= Self.boardedAfter { goal.atStation = false }
        self.goal = goal
        guide.alight(along, on: way)
    }

    /// AT THE STATION
    ///
    /// Riding to the station of a way by train, the way is the router's to
    /// a point on the platform, and nobody rides to that point. They lock
    /// up nowhere, wheel the bike through the station, find the subway,
    /// take the lift, stand on a platform — at Ülemiste across the tracks
    /// from where the router ends. On 2026-11-25 the owner reported what
    /// the app made of it: the last turns of the ride there, then "You're
    /// off the way", then, after half a minute of wheeling the bike, a new
    /// way — by bike, since a new way leaves trains out — which pointed
    /// somewhere else entirely. Their words: it can be silent and let
    /// people find the train, and give an instruction there.
    ///
    /// So within `stationNear` of the station, the way waits. No turn is
    /// said or shown, nobody is told they are off the way, and no new way
    /// is asked, nor taken if one asked on the way there comes back now.
    /// The row says which train to take — its line and where it is going,
    /// the sign on the platform's board — when it leaves, and where to get
    /// off; and the voice says the same once, on arriving (`Guide.station`).
    ///
    /// It waits until the train has the rider — the phone fast enough to
    /// be carried, or `boardedAfter` along the rail — or until they are
    /// `stationLeft` from the station, or `missedAfter` past the time the
    /// train was to leave. Then the way is followed as any is: on the train
    /// as CARRIED, NOT RIDDEN says, and anywhere else as a ride, which off
    /// the way asks a new one in time. It asks nothing of its own.
    ///
    /// True while the way waits, when `add` has nothing more to do with
    /// the point.
    private func platform(_ point: Point) -> Bool {
        guard var goal, case .found(let way) = goal.way, let train = way.train,
              let station = train.boards else { return false }
        let near = Geo.metres(point.coordinate, station)
        let moved = goal.railAlong.map { $0 - train.rail.lowerBound >= Self.boardedAfter } ?? false
        let gone = train.leaves(near: Date(timeIntervalSince1970: point.t))
            .map { point.t - $0.timeIntervalSince1970 > Self.missedAfter } ?? false
        let waits = !carried && !moved && !gone
        if goal.atStation {
            if waits && near <= Self.stationLeft { return true }
            goal.atStation = false
            self.goal = goal
            return false
        }
        // Only on the way there: after the train the rail is behind.
        guard waits, near <= Self.stationNear, goal.along <= train.rail.lowerBound else { return false }
        goal.atStation = true
        goal.lost = nil
        goal.astray = 0
        goal.back = 0
        self.goal = goal
        guide.station(on: way)
        return true
    }

    /// Where the phone is, from a fix the way is not followed by: too
    /// unsure to keep (`unsure`), too fast for a bike between two points
    /// (`add`), or any point while the rider is carried. It moves the row
    /// and nothing else. Plainly far from the way — `farOff` once the fix's
    /// own accuracy is taken off, so one good to 600 m has to be 750 m off —
    /// two fixes running, and the row says so and how far. Nothing is said
    /// aloud and no way is asked from here: a new way waits for a point
    /// that is ridden (`follow`).
    private func note(_ fix: Point) {
        guard var goal = self.goal, goal.lost?.finding != true, case .found(let way) = goal.way else { return }
        // Far from the way, and from every other still on offer.
        let ways = goal.picking == nil ? [way] : goal.ways
        let off = ways.map { $0.place(of: fix.coordinate).off }.min() ?? .infinity
        guard off - fix.acc >= Self.farOff else {
            if goal.adrift > 0 { goal.adrift = 0; self.goal = goal }
            return
        }
        goal.adrift += 1
        if goal.adrift >= Self.astrayPoints {
            if goal.lost?.kind != .off {
                goal.lost = Lost(kind: .off, since: goal.lost?.since ?? (current?.metres ?? 0), metres: off,
                                 failed: goal.lost?.failed)
            }
            goal.lost?.metres = off
        }
        self.goal = goal
    }

    /// Just after a new way, while the website's others are still a choice:
    /// which of them the rider is riding. Nothing is said and nothing is
    /// asked — the phone is in a pocket — and the bike chooses: two points
    /// in a row on one way and off every other, and that one is the way,
    /// the first included. Until then the turns are the first way's, said
    /// only while the rider is on it, and being off it is not "off the way"
    /// while they are on another. Off all of them, or past `pickFor`, the
    /// choice is over and the way is followed as any way is.
    ///
    /// True when the point is dealt with here, and `follow` has nothing
    /// more to do with it.
    private func pick(_ point: Point, in goal: inout Goal, ridden: Double) -> Bool {
        guard let since = goal.picking else { return false }
        let on = goal.ways.indices.filter { goal.ways[$0].place(of: point.coordinate).off <= Way.astray }
        if on.isEmpty || ridden - since >= Self.pickFor {
            endPicking(&goal)
            return false
        }
        if on.count == 1 {
            goal.alonePoints = goal.aloneOn == on[0] ? goal.alonePoints + 1 : 1
            goal.aloneOn = on[0]
        } else {
            goal.aloneOn = nil
            goal.alonePoints = 0
        }
        if let only = goal.aloneOn, goal.alonePoints >= Self.astrayPoints {
            if only != goal.chosen { take(only, in: &goal) }
            endPicking(&goal)
            return false
        }
        // On the way chosen, its turns as ever; on others only, quiet.
        return !on.contains(goal.chosen)
    }

    /// A new way to the same place, from where the rider is now and setting
    /// off the way they are going: somebody who has ridden this far past
    /// "Going the wrong way" means it, and a new way that began "Turn
    /// around" would only say it again. Just off a train (`Goal.alighted`)
    /// nobody is going any way yet, and it is asked with no heading. It takes the place
    /// of the old one, turns and all, and the voice starts over on it; with
    /// no answer, the old one stays and it is asked again later.
    ///
    /// Where the website answers more than one — up to five — the first
    /// is the way and the others are drawn faint beside it with a button
    /// each, and whichever the rider rides on becomes the way (`pick`).
    /// Ways by train are left out: a station is not something to turn
    /// towards mid-ride without being asked.
    private func reroute(from here: CLLocationCoordinate2D, heading: Int?) async {
        guard let asked = goal else { return }
        let ways = await Search.ways(from: here, to: asked.spot.coordinate, heading: heading)
            .filter { $0.train == nil }
        guard var goal = self.goal, goal.spot.id == asked.spot.id else { return }
        // Asked on the way to the station of a way by train and answered
        // once the rider is at it: the train is what they came for, and a
        // way by bike from the platform is the wrong direction (`platform`).
        guard !goal.atStation else {
            goal.lost = nil
            self.goal = goal
            return
        }
        guard !ways.isEmpty else {
            goal.lost?.finding = false
            goal.lost?.failed = Date()
            self.goal = goal
            return
        }
        goal.ways = ways
        take(0, in: &goal)
        endPicking(&goal)
        // Measured from where the ride is now, not where it was asked: the
        // rider has gone on while the website answered.
        if ways.count > 1 { goal.picking = current?.metres ?? 0 }
        self.goal = goal
    }

    /// Save: on disk as waiting first, then sent.
    func save(name: String) async {
        guard let i = currentIndex, rides[i].status == .finished else { return }
        rides[i].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.longestName))
        rides[i].phoneOnly = user == nil
        rides[i].status = .waiting
        goal = nil
        guide.forget()
        shown = rides[i].id
        write(rides[i])
        await sendWaiting(now: true)
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
            // It still says where the phone is: `note`.
            //
            // Judged from the last fix taken, kept or carried. Until
            // 2026-11-25 it was the last one kept, which after a train is
            // the platform it left from, so off any train quicker than
            // 60 km/h door to door every point was still "faster than a
            // bike", on the average of the whole journey, until that
            // average fell: by the sum, forty minutes of riding after the
            // two-hour express from Tallinn to Tartu, carried and never
            // followed.
            var from = last
            if let carried = rides[i].carried?.last, carried.t > last.t { from = carried }
            if Geo.metres(from, point) / max(1, point.t - from.t) > Self.jump { carry(point, in: i); note(point); return }
        }
        // On the train of a way by train, the phone is moving and the bike
        // is not being ridden: a point kept there would save the railway as
        // a bike route, and the website's doors would read it as a shortcut
        // across the tracks. So none is kept as riding: it is carried, the
        // ride goes on from the far station, and the ride's page shows the
        // train as a train.
        if case .found(let way) = goal?.way, let train = way.train {
            let spot = way.place(of: point.coordinate)
            if spot.off <= Way.astray && train.rail.contains(spot.along) {
                // Not riding, but where along the rail the train is, for
                // the row (`Goal.railAlong`) — and, on the platform, where
                // the rider waits for it (`platform`).
                onRail(spot.along, of: way)
                _ = platform(point)
                carry(point, in: i)
                return
            }
        }
        let before = rides[i].points.last
        rides[i].points.append(point)
        if case .found = goal?.way {
            // On a train or in a car the way waits: the point says where
            // the phone is, and no more (CARRIED, NOT RIDDEN).
            // At the station of a way by train it waits too (`platform`).
            if carried {
                note(point)
            } else if !platform(point) {
                follow(point, after: before, ridden: rides[i].metres)
            }
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
    ///
    /// A RIDE THAT FAILS WAITS LONGER EACH TIME
    ///
    /// The app comes to the front and the network comes back many times a
    /// day, and each used to send every waiting ride again. A ride the
    /// server keeps refusing with a word it has no sentence for — or a
    /// server that is out of its day's database reads — was sent again on
    /// every one of them, by every phone, for as long as the app was
    /// installed. Every request costs the site rows read out of a free five
    /// million a day, so now each failure puts the ride off for `retryWait`,
    /// a minute doubling to a cap of six hours. `now` is a person asking —
    /// Save, Try now — and goes past the wait, though never past "often",
    /// which is the server's own date.
    func sendWaiting(now: Bool = false) async {
        guard !sendingNow, !demo else { return }
        sendingNow = true
        defer { sendingNow = false; sendingId = nil }

        var tried = Set<String>()
        while let next = rides.first(where: { $0.status == .waiting && !tried.contains($0.id) && canSend($0, now: now) }) {
            tried.insert(next.id)
            sendingId = next.id
            await send(next.id)
        }
        // Then any place waiting to go on a list, after the rides: a ride is
        // what the app is for.
        await ListBook.shared.sendWaiting(now: now)
    }

    private func canSend(_ ride: Ride, now: Bool) -> Bool {
        guard let notBefore = ride.notBefore, notBefore > Date() else { return true }
        return now && ride.problem != "often"
    }

    /// How long a ride waits after its `tries`-th failure in a row.
    static func retryWait(_ tries: Int) -> TimeInterval {
        min(60 * pow(2, Double(max(0, tries - 1))), 6 * 3600)
    }

    /// Send one ride, and file what the website said.
    ///
    /// A RIDE OUTSIDE THE CITIES STILL ADDS UP ON AN ACCOUNT
    ///
    /// The website takes a line only inside its four cities, and `Geo.line`
    /// leaves the rest out. A ride with nothing inside them (`Ride.outside`)
    /// has no line at all, and until 2026-11-22 it was marked Not kept ·
    /// outside the cities on the phone and never sent. With nobody signed in
    /// it still is: there is nothing to count and nobody to count it for.
    /// Saved signed in, it now goes with an empty line and its `summary`,
    /// and the website adds its numbers up on the account and answers
    /// `counted`, keeping no line — so a rider's totals are every ride they
    /// saved, the one in the countryside included.
    ///
    /// Whether it goes is decided here, at sending, from what was true at
    /// Save and what is true now. Saved with nobody signed in
    /// (`phoneOnly`), it is not sent, whoever has signed in since — the
    /// rule that sends an in-city ride with no session. Saved signed in, it
    /// is sent if the phone still holds the site's session cookie
    /// (`API.holdsSession`), and not on `user`, which is only what `whoAmI`
    /// last heard: nil from launch until the site answers, and for the
    /// whole launch with no signal, which would have filed a signed-in
    /// rider's ride Not kept for good. It goes without `anon`, since with
    /// no account there is nothing to do with it, so a session the site no
    /// longer honours is answered `signed-out`, and the ride is Not kept ·
    /// outside, as it would have been signed out. One request, once, for a
    /// kind of ride that is rare already.
    private func send(_ id: String) async {
        guard let ride = self.ride(id) else { return }
        let outside = ride.outside
        var outcome = ride

        if outside && (ride.phoneOnly == true || !API.holdsSession) {
            outcome.status = .refused
            outcome.problem = "outside"
        } else {
            let line: [[Double]] = outside ? [] : Geo.line(ride.points)
            var body: [String: Any] = [
                "action": "save",
                "name": ride.name,
                // The active time: what the server shares out between the
                // pieces and judges the speed over.
                "seconds": max(1, ride.ridden()),
                "line": line,
                // The whole ride in numbers, for a signed-in rider's
                // account to add up; ignored with no session.
                "summary": ride.summary
            ]
            // Lets a save with no session through, to be counted and not
            // kept; with one, the session wins and the ride is on the
            // account. Not for a ride outside the cities: above.
            if !outside { body["anon"] = true }
            do {
                let data = try await API.post("api/rides", body, signed: ride.phoneOnly != true)
                let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                // `ride` where the website kept it; `counted` and no
                // `ride` where it did not, which leaves the two below nil.
                let saved = object?["ride"] as? [String: Any]
                outcome.status = .saved
                outcome.serverId = saved?["id"] as? String
                outcome.serverMeters = saved?["meters"] as? Int
                outcome.problem = nil
                outcome.notBefore = nil
                outcome.tries = nil
            } catch let refusal as API.Refusal {
                outcome.problem = refusal.code
                switch refusal.code {
                case "short", "fast", "malformed":
                    outcome.status = .refused
                    // A ride outside the cities says why it really was
                    // not kept — the empty line, to a server that does
                    // not take one yet.
                    if outside { outcome.problem = "outside" }
                case "signed-out" where outside:
                    outcome.status = .refused
                    outcome.problem = "outside"
                case "often":
                    outcome.notBefore = Self.nextUTCMidnight()
                default:
                    // 503 not-ready, anything new: try again later.
                    // That includes `signed-out` from a server that does not
                    // take `anon` yet. Later, not at once — see sendWaiting().
                    outcome.tries = (outcome.tries ?? 0) + 1
                    outcome.notBefore = Date().addingTimeInterval(Self.retryWait(outcome.tries ?? 1))
                }
            } catch {
                outcome.problem = "offline"
                outcome.tries = (outcome.tries ?? 0) + 1
                outcome.notBefore = Date().addingTimeInterval(Self.retryWait(outcome.tries ?? 1))
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
