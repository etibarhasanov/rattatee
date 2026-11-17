import MapKit
import SwiftUI

/// The Record tab: a map, and a card at its foot that is one of the states a
/// ride goes through — the same five the website's recorder has, in the same
/// order, plus what only an app needs to say.
///
///   Ready            Start, and the line about the pocket and the battery;
///                    "Where to?" over the map opens the search
///   Going somewhere  the place, the suggested way in blue, and Go
///   Location is off  what to choose in Settings (or Precise Location is)
///   Recording        distance, time, average; Pause and Finish
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
        VStack(spacing: 0) {
            RideMap(points: ride?.points ?? [],
                    goal: store.goal,
                    follow: !store.demo && !planning && (ride == nil || ride?.status == .recording))
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

/// The map: where the phone is, and the line ridden so far.
struct RideMap: View {
    let points: [Point]
    /// Where the rider is going and the suggested way there, in the accent
    /// under the line actually ridden.
    var goal: Goal?
    /// Keep the phone's position in the middle, or show the whole line.
    let follow: Bool

    private static let tallinn = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 59.437, longitude: 24.7536),
        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.12))

    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(RideMap.tallinn))

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            if let goal {
                if case .found(let way) = goal.way {
                    MapPolyline(coordinates: way.line)
                        .stroke(Theme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                Marker(goal.spot.name, coordinate: goal.spot.coordinate).tint(Theme.accent)
            }
            if points.count > 1 {
                MapPolyline(coordinates: points.map(\.coordinate))
                    .stroke(Theme.here, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onAppear { aim() }
        .onChange(of: follow) { aim() }
        .onChange(of: goal) { aim() }
    }

    private func aim() {
        if follow {
            camera = .userLocation(fallback: .region(Self.tallinn))
        } else if points.count > 1 || goal != nil {
            // Everything drawn: the line, the way, the destination.
            camera = .automatic
        }
    }
}

// MARK: Ready

struct ReadyCard: View {
    @Environment(Store.self) private var store

    var body: some View {
        SheetCard {
            Text(L.t("readyTitle")).font(.title2.bold()).foregroundStyle(Theme.ink)
            Note(text: L.t("readyWhy")).padding(.top, 4).padding(.bottom, 14)
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
struct GoalCard: View {
    @Environment(Store.self) private var store
    let goal: Goal

    var body: some View {
        SheetCard {
            Text(goal.spot.name).font(.title2.bold()).foregroundStyle(Theme.ink).lineLimit(2)
            Text(line).font(.subheadline).foregroundStyle(Theme.muted)
            Note(text: note).padding(.top, 10).padding(.bottom, 14)
            Button(L.t("goalGo")) { store.start() }
                .buttonStyle(.big)
        }
    }

    private var line: String {
        var parts = goal.spot.detail.isEmpty ? [] : [goal.spot.detail]
        switch goal.way {
        case .looking: parts.append(L.t("goalFinding"))
        case .found(let way):
            parts.append(L.t("goalWay", ["dist": L.distance(way.metres),
                                         "min": String(max(1, Int((Double(way.seconds) / 60).rounded())))]))
        case .missing: break
        }
        return parts.joined(separator: " · ")
    }

    private var note: String {
        goal.way == .missing ? L.t("goalNoWay") : L.t("goalNote")
    }
}

// MARK: Recording and paused

struct RecordingCard: View {
    @Environment(Store.self) private var store
    let ride: Ride

    var body: some View {
        let recording = ride.status == .recording
        SheetCard {
            HStack(spacing: 8) {
                Circle().fill(recording ? Theme.here : Theme.muted).frame(width: 10, height: 10)
                Text(line(recording))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(recording ? Theme.ink : Theme.muted)
            }
            .padding(.bottom, 8)

            // The clock is the only thing that moves without a new point.
            TimelineView(.periodic(from: .now, by: 1)) { moment in
                RideStats(metres: ride.metres, seconds: ride.seconds(at: moment.date))
            }
            .padding(.bottom, toGo == nil ? 14 : 6)

            if let toGo {
                Text(toGo).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                    .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                if recording {
                    Button(L.t("ridePause")) { store.pause() }.buttonStyle(.bigQuiet)
                } else {
                    Button(L.t("rideResume")) { store.resume() }.buttonStyle(.bigQuiet)
                }
                Button(L.t("rideFinish")) { store.finish() }.buttonStyle(.big)
            }
        }
    }

    /// "To Paper Mill Coffee · 1.1 km left", where the rider said where they
    /// are going: along the suggested way where there is one, and as the
    /// crow flies where there is not.
    private var toGo: String? {
        guard let goal = store.goal else { return nil }
        guard let last = ride.points.last else { return L.t("goalTo", ["name": goal.spot.name]) }
        var left = Geo.metres(last, Point(lat: goal.spot.lat, lng: goal.spot.lng, t: 0, acc: 0))
        if case .found(let way) = goal.way { left = way.left(from: last.coordinate) }
        return L.t("goalLeft", ["name": goal.spot.name, "dist": L.distance(left)])
    }

    private func line(_ recording: Bool) -> String {
        if !recording { return L.t("ridePausedLine") }
        return ride.points.isEmpty ? L.t("rideWaiting") : L.t("rideRecordingLock")
    }
}

/// Distance, time and average, the three numbers of a ride.
struct RideStats: View {
    let metres: Double
    let seconds: Int

    var body: some View {
        HStack(alignment: .top) {
            stat(String(format: "%.1f", metres / 1000), L.t("statKm"))
            stat(L.clock(seconds), L.t("statTime"))
            stat(average, L.t("statAvg"))
        }
    }

    /// Nothing until there is something to divide: the first seconds of a
    /// ride would otherwise read 43 km/h off one point.
    private var average: String {
        guard seconds >= 10, metres >= 50 else { return "–" }
        return String(format: "%.1f", metres / 1000 / (Double(seconds) / 3600))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
