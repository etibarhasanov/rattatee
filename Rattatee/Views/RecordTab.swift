import MapKit
import SwiftUI

/// The Record tab: a map, and a card at its foot that is one of the states a
/// ride goes through — the same five the website's recorder has, in the same
/// order, plus what only an app needs to say.
///
///   Ready            Start, and nothing else to read;
///                    "Where to?" over the map opens the search
///   Going somewhere  the place, the suggested way in blue, and Go
///   Location is off  what to choose in Settings (or Precise Location is)
///   Recording        the screen changes: distance, average and when it
///                    began over the map, Pause and Finish under it
///   Paused           the same, greyed; Resume and Finish
///   Save this ride?  a name, Save ride, Throw it away   (FinishCards.swift)
///   Too short        Keep riding, Throw it away
///   Saved / Kept on this phone / Not kept, once Save has been pressed
struct RecordTab: View {
    @Environment(Store.self) private var store
    @State private var searching = LaunchScript.sheet == "search"

    var body: some View {
        let outcome = store.ride(store.shown)
        let ride = store.current ?? outcome
        // Before a ride, with somewhere to go, the map shows the whole way;
        // otherwise it keeps the phone in the middle while there is no ride
        // or one is being recorded.
        let planning = ride == nil && store.goal != nil
        // Riding is a different screen from getting ready to: the numbers
        // go to the top, where they can be read at a glance off a
        // handlebar, the map takes the middle, and the card at the foot is
        // only its two buttons.
        let riding = store.current.flatMap { [.recording, .paused].contains($0.status) ? $0 : nil }
        VStack(spacing: 0) {
            if let riding { RideDash(ride: riding) }
            RideMap(points: ride?.points ?? [],
                    aside: ride?.aside ?? [],
                    goal: store.goal,
                    here: store.recorder.here,
                    follow: !store.demo && !planning && (ride == nil || ride?.status == .recording),
                    // Somewhere to go is chosen before a ride, never during.
                    tap: ride == nil ? { name, point in store.tapped(name: name, at: point) } : nil)
                .overlay(alignment: .top) {
                    if ride == nil { searchBar }
                }
            card(current: store.current, outcome: outcome)
        }
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .animation(.default, value: store.current?.status)
        .sheet(isPresented: $searching) { SearchSheet() }
        // The way is asked for from where the phone is, which it may only
        // say a moment after the place was chosen.
        .onChange(of: store.recorder.here == nil) { Task { await store.findWay() } }
        // And asked for before anything is chosen, where iOS already lets
        // the app know: a tap then has somewhere to draw its way from, and
        // does not wait on the phone's first fix as well as on the website.
        .onAppear { if store.recorder.allowed { store.recorder.locate() } }
    }

    /// "Where to?", or the place chosen with a cross to let it go. Only
    /// before a ride: once riding, the destination is on the card.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            if let goal = store.goal {
                Text(goal.spot.name).fontWeight(.semibold).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Button { store.goal = nil } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.muted).frame(width: 32, height: 44)
                }
            } else {
                Text(L.t("searchPrompt")).foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { searching = true }
        // Short of the right edge, where the map keeps its locate button.
        .padding(.leading, 16)
        .padding(.trailing, 68)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func card(current: Ride?, outcome: Ride?) -> some View {
        if let current {
            switch current.status {
            case .finished where current.metres < Store.shortest:
                ShortCard(ride: current)
            case .finished:
                SaveCard(ride: current)
            default:
                RecordingCard(ride: current)
            }
        } else if let outcome {
            OutcomeCard(ride: outcome)
        } else if store.recorder.refused || (store.recorder.allowed && !store.recorder.precise) {
            LocationOffCard(approximate: !store.recorder.refused)
        } else if let goal = store.goal {
            GoalCard(goal: goal)
        } else {
            ReadyCard()
        }
    }
}

/// The map: where the phone is, and the line ridden so far. Before a ride a
/// tap on it is somewhere to go: a place Apple's map names, or anywhere.
///
/// THE CAMERA MOVES ONCE FOR SOMEWHERE TO GO
///
/// A tap leaves the map where the rider had it: they zoomed in to choose
/// that corner, and the pin lands under the finger. The camera moves when
/// the way arrives, once, to the whole of it — from where the rider is to
/// the pin. It used to re-frame on every change to the goal, and a tap
/// changes it three times: the pin, the pin's street from the geocoder, and
/// the way. The first of those threw away the rider's zoom for a frame of
/// the pin alone, and the third moved it again, which read as the map
/// loading something in between.
///
/// Until the way arrives a dotted straight line runs from the rider to the
/// pin, so from where to where is on the map at once and the wait for the
/// website has something to look at. A place chosen in the search may be
/// off the screen; that one is framed straight away, rider and place, and
/// the way then settles inside nearly the same frame.
struct RideMap: View {
    let points: [Point]
    /// The stretches Finish set aside as walked or driven: dotted and faint,
    /// so they read as where the rider went and not as a way to ride.
    var aside: [[Point]] = []
    /// Where the rider is going and the suggested way there, in the accent
    /// under the line actually ridden.
    var goal: Goal?
    /// Where the phone last said it was: the near end of the dotted line
    /// and of the frame the way is shown in.
    var here: CLLocationCoordinate2D?
    /// Keep the phone's position in the middle, or show the whole line.
    let follow: Bool
    /// A tap: the name of the place Apple's map drew there, if it drew one,
    /// and the point. Nil while riding, when taps do nothing.
    var tap: ((String?, CLLocationCoordinate2D) -> Void)?

    private static let tallinn = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 59.437, longitude: 24.7536),
        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.12))

    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(RideMap.tallinn))
    /// The place Apple's map drew under a tap, which it selects by itself.
    @State private var picked: MapFeature?
    /// When it last did, so the tap under it does not drop a pin as well.
    @State private var pickedAt = Date.distantPast
    /// What the map is showing, as of the last time it came to rest: how a
    /// place just chosen is known to be on the screen already, or not.
    @State private var seen: MKCoordinateRegion?

    var body: some View {
        GeometryReader { frame in
            MapReader { proxy in
                map
                    // Beside the map's own gestures rather than instead of
                    // them: dragging and pinching go on as before.
                    .simultaneousGesture(SpatialTapGesture().onEnded { tapped in
                        guard tap != nil, !onControls(tapped.location, width: frame.size.width),
                              let point = proxy.convert(tapped.location, from: .local) else { return }
                        Task { @MainActor in
                            // A tap on a named place selects it a moment
                            // later; wait for that, and drop a pin only if
                            // it did not.
                            try? await Task.sleep(for: .milliseconds(250))
                            guard Date().timeIntervalSince(pickedAt) > 0.6 else { return }
                            tap?(nil, point)
                        }
                    })
            }
        }
        .onChange(of: picked) {
            guard let feature = picked else { return }
            pickedAt = Date()
            tap?(feature.title, feature.coordinate)
            picked = nil
        }
    }

    private var map: some View {
        Map(position: $camera, selection: $picked) {
            UserAnnotation()
            if let goal {
                if case .found(let way) = goal.way {
                    // The ways on offer and not chosen, faint under the
                    // one that is: before a ride only, while it is still
                    // a choice.
                    if points.isEmpty {
                        ForEach(Array(goal.ways.enumerated()).filter { $0.offset != goal.chosen }, id: \.offset) { _, other in
                            MapPolyline(coordinates: other.line)
                                .stroke(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                    }
                    if let train = way.train {
                        // A way by train: the rides solid, as any way, and
                        // the rail dashed, so it is not read as a road.
                        ForEach(Array(train.legs.enumerated()), id: \.offset) { _, leg in
                            MapPolyline(coordinates: leg.line)
                                .stroke(Theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round,
                                                                                         dash: leg.bike ? [] : [8, 8]))
                        }
                    } else {
                        MapPolyline(coordinates: way.line)
                            .stroke(Theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                } else if goal.way == .looking, points.isEmpty, let here {
                    // As the crow flies, until the website says how a bike
                    // goes. Dotted, so it is not read as a way to ride.
                    MapPolyline(coordinates: [here, goal.spot.coordinate])
                        .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 9]))
                }
                Marker(goal.spot.name, coordinate: goal.spot.coordinate).tint(Theme.accent)
            }
            ForEach(Array(aside.enumerated()), id: \.offset) { _, stretch in
                if stretch.count > 1 {
                    MapPolyline(coordinates: stretch.map(\.coordinate))
                        .stroke(Theme.muted, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
                }
            }
            ForEach(Array(Geo.runs(points, around: aside).enumerated()), id: \.offset) { _, run in
                if run.count > 1 {
                    MapPolyline(coordinates: run.map(\.coordinate))
                        .stroke(Theme.here, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .mapFeatureSelectionDisabled { feature in tap == nil || feature.kind != .pointOfInterest }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { seen = $0.region }
        .onAppear { aim() }
        // Choosing somewhere to go stops the following and moves nothing;
        // letting it go, or starting to ride, takes the camera back.
        .onChange(of: follow) { if follow || goal == nil { aim() } }
        // By the place and by the way, never by the goal whole: a pin's
        // street arriving is a change to the goal and no reason to move.
        .onChange(of: goal?.spot.id) {
            // Off the screen, or arriving with its way already found (a
            // staged screen does): there is no later moment to frame it at.
            if !follow, let goal, !inView(goal.spot.coordinate) || goal.way != .looking { settle(goal) }
        }
        // And not by which way is chosen: all of them are in the frame.
        .onChange(of: goal?.way == .looking) {
            if !follow, let goal, goal.way != .looking { settle(goal) }
        }
    }

    /// The corner where the map draws its locate button and compass, which
    /// the tap gesture beside it would otherwise hear as a pin as well.
    private func onControls(_ at: CGPoint, width: CGFloat) -> Bool {
        at.x > width - 64 && at.y < 140
    }

    private func aim() {
        if follow {
            camera = .userLocation(fallback: .region(Self.tallinn))
        } else if points.count > 1 {
            // Everything drawn: the line, the way, the destination.
            camera = .automatic
        } else if let goal {
            settle(goal)
        }
    }

    /// Whether a point is on the screen, as far as the map has said. Before
    /// it has said anything, it is not.
    private func inView(_ at: CLLocationCoordinate2D) -> Bool {
        guard let seen else { return false }
        return abs(at.latitude - seen.center.latitude) < seen.span.latitudeDelta / 2
            && abs(at.longitude - seen.center.longitude) < seen.span.longitudeDelta / 2
    }

    /// Show the whole of somewhere to go: the rider, the place, and the way
    /// between them where there is one. Framed by hand rather than left to
    /// `.automatic`, which does not promise to count the rider's own dot.
    private func settle(_ goal: Goal) {
        var all = [goal.spot.coordinate]
        if let here { all.append(here) }
        if case .found(let way) = goal.way { all += way.line }
        // Every way on offer, so choosing another moves nothing.
        for other in goal.ways { all += other.line }
        let spots = all.map { MKMapPoint($0) }
        guard let west = spots.map(\.x).min(), let east = spots.map(\.x).max(),
              let north = spots.map(\.y).min(), let south = spots.map(\.y).max() else { return }
        // A quarter again on three sides, and half again on top, which
        // clears the search bar and the pin's own height — with a quarter
        // there the pin stood under the bar on CI's staged screen. Never
        // closer than a few streets, for a pin dropped beside the rider.
        let least = 400 * MKMapPointsPerMeterAtLatitude(goal.spot.lat)
        let width = max(east - west, least), height = max(south - north, least)
        let middle = (west + east) / 2, top = (north + south) / 2 - height / 2
        let rect = MKMapRect(x: middle - width * 0.75, y: top - height * 0.5,
                             width: width * 1.5, height: height * 1.75)
        withAnimation { camera = .rect(rect) }
    }
}

// MARK: Ready

struct ReadyCard: View {
    @Environment(Store.self) private var store

    var body: some View {
        SheetCard {
            // Nothing to read: the map says where, and the button what.
            Button(L.t("rideStart")) { store.start() }
                .buttonStyle(.big)
        }
    }
}

struct LocationOffCard: View {
    /// Location is allowed but only approximately: Precise Location is off.
    var approximate = false

    var body: some View {
        SheetCard {
            Text(approximate ? L.t("locPreciseTitle") : L.t("locOffTitle")).font(.title2.bold()).foregroundStyle(Theme.ink)
            Note(text: approximate ? L.t("locPreciseWhy") : L.t("locOffWhy")).padding(.top, 4).padding(.bottom, 14)
            Button(L.t("openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.big)
        }
    }
}

/// Somewhere to go: the place, how far by the suggested way, and Go, which
/// is Start. The way is a suggestion and says so; what is recorded is where
/// the rider really went.
///
/// A place — not a street — can also go on one of the rider's lists on the
/// website, which needs an account: signed in, Add to a list beside Go;
/// signed out, a line saying so.
struct GoalCard: View {
    @Environment(Store.self) private var store
    let goal: Goal
    @State private var listing = false

    var body: some View {
        let listable = goal.spot.kind != .street
        SheetCard {
            Text(goal.spot.name).font(.title2.bold()).foregroundStyle(Theme.ink).lineLimit(2)
            Text(line).font(.subheadline).foregroundStyle(Theme.muted)
            if goal.ways.count > 1 { ways }
            // "No way found" outranks the sign-in line: it is about the ride.
            Note(text: listable && store.user == nil && goal.way != .missing ? L.t("goalListSignIn") : note)
                .padding(.top, 10).padding(.bottom, 14)
            HStack(spacing: 10) {
                if listable && store.user != nil {
                    Button(L.t("goalList")) { listing = true }.buttonStyle(.bigQuiet)
                }
                Button(L.t("goalGo")) { store.start() }.buttonStyle(.big)
            }
        }
        .sheet(isPresented: $listing) { ListPicker(spot: goal.spot) }
    }

    /// The ways on offer, a small button each — how long and how far, as
    /// on the website's route bar, and nothing about which is nicer, since
    /// the router does not say. The one chosen is filled, and is the solid
    /// line on the map; Go starts with it.
    private var ways: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(goal.ways.enumerated()), id: \.offset) { index, way in
                    let on = index == goal.chosen
                    Button {
                        store.choose(way: index)
                    } label: {
                        Text(chip(way))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
                            .background(on ? Theme.accent : Theme.wash, in: Capsule())
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.top, 10)
    }

    /// A way's button: how long and how far, or for a way by train how
    /// long and when the train goes, since that is what it hangs on.
    private func chip(_ way: Way) -> String {
        let min = String(max(1, Int((Double(way.seconds) / 60).rounded())))
        if let train = way.train { return L.t("goalTrainChip", ["min": min, "at": train.at]) }
        return L.t("goalWayChip", ["min": min, "dist": L.distance(way.metres)])
    }

    private var line: String {
        var parts = goal.spot.detail.isEmpty ? [] : [goal.spot.detail]
        switch goal.way {
        case .looking: parts.append(L.t("goalFinding"))
        case .found(let way):
            let min = String(max(1, Int((Double(way.seconds) / 60).rounded())))
            if let train = way.train {
                parts.append(L.t("goalTrain", ["leave": train.leave, "from": train.from, "line": train.name,
                                               "at": train.at, "to": train.to, "min": min]))
            } else {
                parts.append(L.t("goalWay", ["dist": L.distance(way.metres), "min": min]))
            }
        case .missing: break
        }
        return parts.joined(separator: " · ")
    }

    private var note: String {
        goal.way == .missing ? L.t("goalNoWay") : L.t("goalNote")
    }
}

// MARK: Recording and paused

/// The top of the screen while riding: three numbers and no more, at the
/// owner's word — how far, how fast on average, and when it began. No
/// running clock, no speed right now and no top speed: a phone's speed
/// between two fixes jumps about, and an average over the whole ride is the
/// one number of the three kinds that is true. Under them, where the rider
/// said where they are going, how much of the way is left.
struct RideDash: View {
    @Environment(Store.self) private var store
    let ride: Ride

    var body: some View {
        let recording = ride.status == .recording
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(recording ? Theme.here : Theme.muted).frame(width: 10, height: 10)
                Text(line(recording))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(recording ? Theme.ink : Theme.muted)
            }
            .padding(.bottom, 6)

            // The average is the only number that moves without a new
            // point: the clock under it runs on.
            TimelineView(.periodic(from: .now, by: 1)) { moment in
                HStack(alignment: .firstTextBaseline) {
                    stat(String(format: "%.1f", ride.metres / 1000), L.t("statKm"), big: true)
                    stat(Self.average(ride.metres, ride.seconds(at: moment.date)), L.t("statAvg"), big: true)
                    stat(L.time(ride.started), L.t("statStarted"), big: false)
                }
            }

            if let toGo {
                Text(toGo).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                    .padding(.top, 8)
            }

            if let lost = store.goal?.lost {
                Divider().overlay(Theme.hairline).padding(.top, 10)
                LostRow(lost: lost).padding(.top, 10)
            } else if let next {
                Divider().overlay(Theme.hairline).padding(.top, 10)
                TurnRow(step: next.step, metres: next.metres).padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.ignoresSafeArea(edges: .top))
    }

    private func stat(_ value: String, _ label: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: big ? 46 : 30, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(ride.status == .recording ? Theme.ink : Theme.muted)
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nothing until there is something to divide: the first seconds of a
    /// ride would otherwise read 43 km/h off one point.
    static func average(_ metres: Double, _ seconds: Int) -> String {
        guard seconds >= 10, metres >= 50 else { return "–" }
        return String(format: "%.1f", metres / 1000 / (Double(seconds) / 3600))
    }

    /// "To Paper Mill Coffee · 1.1 km left", where the rider said where they
    /// are going: along the suggested way where there is one, and as the
    /// crow flies where there is not — or where the rider is off it, when
    /// what is left of a way they are not on means nothing, and the line
    /// says "away" instead of "left".
    private var toGo: String? {
        guard let goal = store.goal else { return nil }
        guard let last = ride.points.last else { return L.t("goalTo", ["name": goal.spot.name]) }
        let crow = Geo.metres(last, Point(lat: goal.spot.lat, lng: goal.spot.lng, t: 0, acc: 0))
        if goal.lost?.kind == .off { return L.t("goalAway", ["name": goal.spot.name, "dist": L.distance(crow)]) }
        var left = crow
        if case .found(let way) = goal.way { left = way.left(from: last.coordinate) }
        return L.t("goalLeft", ["name": goal.spot.name, "dist": L.distance(left)])
    }

    /// The corner coming up on the way there, where the website said where
    /// the way turns and the rider is still on it.
    private var next: (step: Step, metres: Double)? {
        guard case .found(let way) = store.goal?.way, let last = ride.points.last else { return nil }
        return way.next(from: last.coordinate)
    }

    private func line(_ recording: Bool) -> String {
        if !recording { return L.t("ridePausedLine") }
        return ride.points.isEmpty ? L.t("rideWaiting") : L.t("rideRecording")
    }
}

/// The next turn, under the numbers: an arrow, how far, what to do and the
/// street it is onto, and the switch for the voice that says the same. The
/// street is beside the words rather than in them — "onto Narva maantee" is
/// a case ending in Estonian that nothing here can decline.
struct TurnRow: View {
    @Environment(Store.self) private var store
    let step: Step
    let metres: Double

    var body: some View {
        let voice = store.guide.voice
        HStack(spacing: 12) {
            Image(systemName: step.turn.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text(L.distance(metres)).font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(step.name.isEmpty ? step.words : step.words + " · " + step.name)
                    .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { store.guide.voice.toggle() } label: {
                Image(systemName: voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(voice ? Theme.accent : Theme.muted)
                    .frame(width: 44, height: 44)
                    .background(Theme.wash, in: Circle())
            }
            .accessibilityLabel(voice ? L.t("voiceOn") : L.t("voiceOff"))
        }
    }
}

/// In the turn row's place while the rider is off the way or riding it
/// backwards: what has happened, and then that a new way is being looked
/// for — which happens by itself, so there is nothing to press but the
/// speaker. The icon is on the quiet ground rather than the accent: it is
/// news, not an instruction.
struct LostRow: View {
    @Environment(Store.self) private var store
    let lost: Lost

    var body: some View {
        let voice = store.guide.voice
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.wash, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text(words.0).font(.title3.weight(.bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(words.1).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { store.guide.voice.toggle() } label: {
                Image(systemName: voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .foregroundStyle(voice ? Theme.accent : Theme.muted)
                    .frame(width: 44, height: 44)
                    .background(Theme.wash, in: Circle())
            }
            .accessibilityLabel(voice ? L.t("voiceOn") : L.t("voiceOff"))
        }
    }

    private var symbol: String {
        if lost.finding { return "arrow.triangle.2.circlepath" }
        return lost.kind == .off ? "exclamationmark" : "arrow.uturn.backward"
    }

    private var words: (String, String) {
        if lost.finding { return (L.t("lostFinding"), L.t("lostFindingWhy")) }
        if lost.failed != nil { return (L.t("lostNone"), L.t("lostNoneWhy")) }
        switch lost.kind {
        case .off: return (L.t("lostOff"), L.t("lostOffFrom", ["dist": L.distance(lost.metres)]))
        case .back: return (L.t("lostBack"), L.t("lostBackWhy"))
        }
    }
}

/// The foot of the screen while riding: Pause or Resume, and Finish.
struct RecordingCard: View {
    @Environment(Store.self) private var store
    let ride: Ride

    var body: some View {
        SheetCard {
            HStack(spacing: 10) {
                if ride.status == .recording {
                    Button(L.t("ridePause")) { store.pause() }.buttonStyle(.bigQuiet)
                } else {
                    Button(L.t("rideResume")) { store.resume() }.buttonStyle(.bigQuiet)
                }
                Button(L.t("rideFinish")) { store.finish() }.buttonStyle(.big)
            }
        }
    }
}
