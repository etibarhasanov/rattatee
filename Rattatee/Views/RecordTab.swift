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
///                    began over the map, Pause and Finish under it, and
///                    "Where to?" still over the map, to choose mid-ride
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
                    // Somewhere to go is chosen before a ride or during one,
                    // with no need to pause or finish. While riding, a
                    // touch chooses only where there is nowhere to go yet:
                    // a hand resting on the screen should not throw away a
                    // way the rider is following. Where to? and its cross
                    // change it on purpose. Before a ride the map makes
                    // somewhere chosen harder to move by itself: no tap
                    // moves it, and the hold is a second (`RideMap`).
                    touch: canTouch ? { name, point in store.touched(name: name, at: point) } : nil,
                    // A tap on a faint line is a press on its button, and
                    // works where the buttons are: on the card before a
                    // ride, and under the numbers during one.
                    choose: (ride == nil || riding != nil) ? { index in store.choose(way: index) } : nil)
                .overlay(alignment: .top) {
                    if ride == nil || riding != nil { searchBar }
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
        // the app know: a pin then has somewhere to draw its way from, and
        // does not wait on the phone's first fix as well as on the website.
        .onAppear { if store.recorder.allowed { store.recorder.locate() } }
    }

    /// Whether a touch on the map is somewhere to go — a tap on a place it
    /// names, a hold anywhere: before a ride, and while riding or paused
    /// with nowhere to go yet — never on the save card or after it.
    private var canTouch: Bool {
        guard let current = store.current else { return store.ride(store.shown) == nil }
        return [.recording, .paused].contains(current.status) && store.goal == nil
    }

    /// "Where to?", or the place chosen with a cross to let it go. Before a
    /// ride and while riding: a destination can be chosen, changed or let go
    /// mid-ride, and the recording goes on underneath.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            if let goal = store.goal {
                Text(goal.spot.name).fontWeight(.semibold).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Button {
                    // Mid-ride the voice was following it too: it starts
                    // afresh on whatever is chosen next.
                    store.goal = nil
                    store.guide.forget()
                } label: {
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
            if goal.ways.count > 1 { WayChips(goal: goal) }
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

/// The ways on offer, a small button each — how long and how far, as on the
/// website's route bar, and nothing about which is nicer, since the router
/// does not say. The one chosen is filled, and is the solid line on the map;
/// a tap on one of the faint lines there is a press on its button here.
/// A way by train is filled in the trains' orange, as its rail is drawn.
/// On the card before a ride, where Go starts with the one chosen; and under
/// the numbers just after a new way mid-ride, where riding one chooses it
/// just as well as a press does.
struct WayChips: View {
    @Environment(Store.self) private var store
    let goal: Goal

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(goal.ways.enumerated()), id: \.offset) { index, way in
                    let on = index == goal.chosen
                    // A way by train's button is the orange its rail is
                    // on the map: the stretch that makes it another kind of
                    // way, and its button, are the one colour.
                    let fill = way.train == nil ? Theme.accent : Theme.train
                    let onFill = way.train == nil ? Theme.onAccent : Theme.onTrain
                    Button {
                        store.choose(way: index)
                    } label: {
                        Text(chip(way))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .foregroundStyle(on ? onFill : Theme.ink)
                            .background(on ? fill : Theme.wash, in: Capsule())
                    }
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.top, 10)
    }

    /// A way's button: how long and how far, or for a way by train how
    /// long and when the train goes, since that is what it hangs on. Where
    /// the website says what kind of way it is, that comes first.
    private func chip(_ way: Way) -> String {
        let min = String(max(1, Int((Double(way.seconds) / 60).rounded())))
        if let train = way.train { return L.t("goalTrainChip", ["min": min, "at": train.at]) }
        let gaps = ["min": min, "dist": L.distance(way.metres)]
        switch way.style {
        case .ridden: return L.t("goalWayRidden", gaps)
        case .fastest: return L.t("goalWayFastest", gaps)
        case .safest: return L.t("goalWaySafest", gaps)
        case .quietest: return L.t("goalWayQuietest", gaps)
        case .shortest: return L.t("goalWayShortest", gaps)
        case nil: return L.t("goalWayChip", gaps)
        }
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

            // A new way off the old one, with others beside it: the same
            // buttons as on the card before a ride, for as long as riding
            // has not chosen. Nothing is said about them.
            if let goal = store.goal, goal.picking != nil, goal.ways.count > 1 {
                WayChips(goal: goal)
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
/// street it is onto. The street is beside the words rather than in them —
/// "onto Narva maantee" is a case ending in Estonian that nothing here can
/// decline. The switch for the voice that says the same was a speaker at
/// the end of this row until 2026-11-22; it is at the foot now, beside the
/// radio (`VoiceButton`).
struct TurnRow: View {
    let step: Step
    let metres: Double

    var body: some View {
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
        }
    }
}

/// In the turn row's place while the rider is off the way or riding it
/// backwards: what has happened, and then that a new way is being looked
/// for — which happens by itself, so there is nothing here to press. The
/// icon is on the quiet ground rather than the accent: it is news, not an
/// instruction.
struct LostRow: View {
    let lost: Lost

    var body: some View {
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

/// The foot of the screen while riding: the radio, with the voice's button
/// at its end where there is somewhere to go, and under them Pause or
/// Resume, and Finish.
struct RecordingCard: View {
    @Environment(Store.self) private var store
    let ride: Ride

    var body: some View {
        SheetCard {
            HStack(spacing: 10) {
                RadioRow()
                if store.goal != nil { VoiceButton() }
            }
            .padding(.bottom, 10)
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

/// The switch for the voice that says the turns, at the end of the radio's
/// row: a square with a speaker and one word, the size of the row it ends.
///
/// At the owner's word on 2026-11-22, two buttons at the foot, one for the
/// music and one for the voice. Until then the voice's switch was a small
/// speaker at the end of the turn row, up among the numbers, where it was
/// easy to miss. It is shown only while there is somewhere to go — from
/// the moment one is chosen, so it does not come and go while a way is
/// being looked for. With nowhere to go the voice says nothing but the
/// greeting at Start, and a button that switched nothing would only take
/// the radio's room. The radio keeps its row and its next and previous: it
/// is narrower by this square and no more.
///
/// On, the speaker is in the accent and the word is "Voice"; off, both are
/// muted and the word is "Off". The ground is the quiet one either way: the
/// voice is on unless somebody turned it off, and the accent ground is for
/// the radio while it plays.
struct VoiceButton: View {
    @Environment(Store.self) private var store

    var body: some View {
        let voice = store.guide.voice
        Button { store.guide.voice.toggle() } label: {
            VStack(spacing: 2) {
                Image(systemName: voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(voice ? Theme.accent : Theme.muted)
                Text(voice ? L.t("voiceShort") : L.t("voiceShortOff"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(voice ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 64, height: 56)
            .background(Theme.wash, in: RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice ? L.t("voiceOn") : L.t("voiceOff"))
    }
}
