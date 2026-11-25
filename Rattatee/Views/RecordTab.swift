import MapKit
import SwiftUI

/// The Record tab: a map, and a card at its foot that is one of the states a
/// ride goes through.
///
///   Ready            Start, and nothing else to read;
///                    "Where to?" over the map opens the search
///   Going somewhere  the place, the suggested way in the colour chosen
///                    under Account, and Go
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
        // And asked for before anything is chosen: a pin then has somewhere
        // to draw its way from, and does not wait on the phone's first fix
        // as well as on the website. On a new install this is where iOS asks
        // the location question — the map is the first thing the app shows,
        // and without it the map has no blue dot until Start is pressed.
        // Once refused, `locate()` asks nothing; Start says how to allow it.
        .onAppear { store.recorder.locate() }
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

/// Somewhere to go: the place, the way chosen as a row, and Go, which is
/// Start. The way is a suggestion and says so; what is recorded is where
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
            // A pin whose street has not come yet has nothing to say here,
            // and no line is better than an empty one.
            if !line.isEmpty { Text(line).font(.subheadline).foregroundStyle(Theme.muted) }
            if case .found(let way) = goal.way { WayRow(way: way).padding(.top, 12) }
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

    /// Under the name: where the place is and what kind it is, and, until
    /// the website answers, that a way is being looked for. The way itself
    /// is the row under this (`WayRow`).
    private var line: String {
        var parts = goal.spot.detail.isEmpty ? [] : [goal.spot.detail]
        if goal.way == .looking { parts.append(L.t("goalFinding")) }
        return parts.joined(separator: " · ")
    }

    private var note: String {
        goal.way == .missing ? L.t("goalNoWay") : L.t("goalNote")
    }
}

/// The way chosen, on the card before a ride, as a row the way Google's map
/// lists a journey: how long it takes, and then what it is made of.
///
/// THE WAY IS A ROW, NOT A SENTENCE
///
/// By bike that is how far, and *Ridden* where riders have been along it:
///
///     18 min   3.6 km
///
/// By train it is three lines: when to set off and when the rider is at the
/// door; a ride, the train and a ride as a pill each, the rides with their
/// minutes and the train in its orange with its name; and the train's own
/// two times and stations.
///
///     14 min   17:26 – 17:40
///              (bike 6) › (train R31) › (bike 1)
///              17:34 Kitseküla → 17:39 Tallinn
///
/// Until 2026-11-23 all of that was one sentence after the address —
/// "Leave at 17:26: ride to Kitseküla, the R31 at 17:34 to Tallinn, ride
/// on · 14 min" — three lines of grey to read through for a time. The owner
/// sent it beside Google's list of buses that day and asked for something
/// like that. The sentence is still what VoiceOver reads, since a row of
/// pills is nothing to listen to.
///
/// Nothing in the row is a sentence, so nothing in it has to be declined:
/// the times and names are the website's, and the two words are `min` and
/// `Ridden`. The minutes in the pills are the rides alone and do not add up
/// to the whole: the train's own minutes and the two on the platform the
/// website counts are in the figure at the front and in no pill. The time
/// at the door is `leave` and that same figure on, so the two agree.
///
/// The buttons under the row stay, at the owner's choice of the two ways
/// this was drawn: a row for every way was the other, and cost the map a
/// quarter of its height where there are three ways. So the row says again
/// what the chosen button says, and for a way by train says the rest.
struct WayRow: View {
    let way: Way

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(way.minutes)).font(.title3.bold()).foregroundStyle(Theme.ink)
                Text(L.t("goalMin")).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            if let train = way.train {
                VStack(alignment: .leading, spacing: 4) {
                    Text(times(train)).font(.headline).foregroundStyle(Theme.ink)
                    legs(train)
                    Text(train.journey).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                }
            } else {
                Text(L.distance(way.metres)).font(.headline).foregroundStyle(Theme.ink)
                if way.style == .ridden {
                    Text(L.t("goalRidden")).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(said)
    }

    /// "17:26 – 17:40": setting off, and at the door.
    private func times(_ train: Train) -> String {
        guard let arrive = train.arrive(after: way.minutes) else { return train.leave }
        return train.leave + " – " + arrive
    }

    /// A ride, the train, a ride, with an arrow between: each a pill. The
    /// train's says where it is going after its name, "RE33 Narva", as the
    /// front of the train does (`Train.sign`).
    private func legs(_ train: Train) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(train.legs.enumerated()), id: \.offset) { index, leg in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                if leg.bike {
                    LegPill(symbol: "bicycle", text: leg.minutes.map { String($0) } ?? "",
                            ink: Theme.ink, ground: Theme.wash)
                } else {
                    LegPill(symbol: "tram.fill", text: train.sign, ink: Theme.onTrain, ground: Theme.train)
                }
            }
        }
    }

    /// What VoiceOver reads in the row's place: the whole of it, as the
    /// sentence the card used to print.
    private var said: String {
        let min = String(way.minutes)
        guard let train = way.train else { return L.t("goalWay", ["dist": L.distance(way.metres), "min": min]) }
        return L.t("goalTrain", ["leave": train.leave, "from": train.from, "line": train.name,
                                 "at": train.at, "to": train.to, "min": min])
    }
}

/// One leg of a way by train: what it is by, and beside it how many minutes
/// or which train. The picture alone, where the website did not say.
struct LegPill: View {
    let symbol: String
    let text: String
    let ink: Color
    let ground: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption)
            if !text.isEmpty { Text(text).font(.footnote.weight(.semibold)).lineLimit(1) }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
        .foregroundStyle(ink)
        .background(ground, in: Capsule())
    }
}

/// Which train, under where the rider is going, for as long as it is still
/// ahead or being ridden: the train's pill as the card had it, "RE33 Narva",
/// and its two times and stations.
///
///     (train RE33 Narva)  06:25 Tallinn → 06:33 Ülemiste
///
/// WHAT THE PLATFORM SAYS
///
/// The card says all of this before Go and then it was gone: riding to the
/// station, the screen had an arrow and a distance. And what it had said of
/// the train was where to get off, which no sign at a station says. The
/// board over a platform and the front of a train name where the train is
/// going — Narva, for somebody riding two stops to Ülemiste — and at a
/// station whose platforms are a subway apart that word is the one to
/// follow. The owner asked for it from a station on 2026-11-25: say which
/// sign, the direction or the train's number. This is both, and the time,
/// for the whole ride there, since whether the train will be caught is the
/// other thing worth a glance.
///
/// Nothing in it is a sentence, as nothing on the card is. VoiceOver reads
/// the sentence the voice says (`Train.sentence`).
struct TrainLine: View {
    let train: Train

    var body: some View {
        HStack(spacing: 8) {
            LegPill(symbol: "tram.fill", text: train.sign, ink: Theme.onTrain, ground: Theme.train)
            Text(train.journey).font(.footnote).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Train.sentence(train.gaps))
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
        let min = String(way.minutes)
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

            if let train = boarding {
                TrainLine(train: train).padding(.top, 6)
            }

            // At the station of a way by train, which train to take, and
            // nothing about turns (AT THE STATION in Store.swift). On the
            // train, how far to the station to get off at. On any other
            // train no turn is a turn to take (CARRIED, NOT RIDDEN there).
            if let train = boarding, store.goal?.atStation == true {
                Divider().overlay(Theme.hairline).padding(.top, 10)
                TrainRow(title: L.t("trainTake", ["sign": train.sign]),
                         words: L.t("trainLeaves", ["at": train.at, "to": train.to]))
                    .padding(.top, 10)
            } else if let lost = store.goal?.lost {
                Divider().overlay(Theme.hairline).padding(.top, 10)
                LostRow(lost: lost).padding(.top, 10)
            } else if let train = boarding, let along = store.goal?.railAlong {
                Divider().overlay(Theme.hairline).padding(.top, 10)
                TrainRow(title: L.distance(max(0, train.rail.upperBound - along)),
                         words: L.t("trainGetOff", ["to": train.to]))
                    .padding(.top, 10)
            } else if let next, !store.carried || next.step.turn == .train {
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
        guard let at else { return L.t("goalTo", ["name": goal.spot.name]) }
        let crow = Geo.metres(at, Point(lat: goal.spot.lat, lng: goal.spot.lng, t: 0, acc: 0))
        if goal.lost?.kind == .off { return L.t("goalAway", ["name": goal.spot.name, "dist": L.distance(crow)]) }
        var left = crow
        if case .found(let way) = goal.way { left = way.left(from: at.coordinate) }
        return L.t("goalLeft", ["name": goal.spot.name, "dist": L.distance(left)])
    }

    /// The train of the way being ridden, until its rail is behind: on the
    /// ride to the station and on the train itself.
    private var boarding: Train? {
        guard let goal = store.goal, case .found(let way) = goal.way, let train = way.train,
              goal.along <= train.rail.upperBound else { return nil }
        return train
    }

    /// Where that is measured from: the ride's last point — or, once the
    /// phone is a gap from it with nothing kept since, where the phone last
    /// said it was, however sure. On a train no point is kept, and the line
    /// said "3.7 km away" of a place the train was pulling in beside. The
    /// next corner is still found from the last point: on the train of a
    /// way by train that is the station's row, which says where to get off.
    /// A staged ride is measured from its own points, wherever the
    /// simulator says it is.
    private var at: Point? {
        guard let last = ride.points.last else { return nil }
        guard !store.demo, let here = store.recorder.here else { return last }
        let phone = Point(lat: here.latitude, lng: here.longitude, t: 0, acc: 0)
        return Geo.metres(last, phone) > Geo.gap ? phone : last
    }

    /// The corner coming up on the way there, where the website said where
    /// the way turns and the rider is still on it, from the last point
    /// ridden. On the train of a way by train no point is ridden, and until
    /// 2026-11-25 this said the last turn before the platform for the whole
    /// train — "60 m · Turn left", half a kilometre out of Ülemiste — where
    /// the row is now the train's own (`TrainRow`).
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

/// The row of a way by train where a turn's would be, on the train's own
/// orange as its pill is. At its station, which train to take — "Take the
/// RE33 Narva", the sign on the platform's board — when it leaves and where
/// to get off; on it, how far to the station to get off at. Never a
/// distance to the platform: nobody rides to the point the router ends at,
/// and that is what went wrong at Ülemiste (AT THE STATION in
/// Store.swift).
struct TrainRow: View {
    let title: String
    let words: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Turn.train.symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.onTrain)
                .frame(width: 44, height: 44)
                .background(Theme.train, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                // Two lines where one will not do: in Russian the station
                // to get off at, the one word that matters, was cut off.
                Text(words).font(.subheadline).foregroundStyle(Theme.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
///
/// A build without the radio (`Radio.offered`, so every release for now)
/// has no row for it. The voice's button moves to the start of the Pause
/// and Finish row, the same height as them, and the card is one row
/// shorter, so the map has that much more room.
struct RecordingCard: View {
    @Environment(Store.self) private var store
    let ride: Ride

    var body: some View {
        SheetCard {
            if Radio.offered {
                HStack(spacing: 10) {
                    RadioRow()
                    if store.goal != nil { VoiceButton() }
                }
                .padding(.bottom, 10)
            }
            HStack(spacing: 10) {
                if !Radio.offered && store.goal != nil { VoiceButton() }
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
