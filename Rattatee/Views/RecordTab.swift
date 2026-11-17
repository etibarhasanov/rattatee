import MapKit
import SwiftUI

/// The Record tab: a map, and a card at its foot that is one of the states a
/// ride goes through — the same five the website's recorder has, in the same
/// order, plus what only an app needs to say.
///
///   Ready            Start, and the line about the pocket and the battery
///   Location is off  what to choose in Settings
///   Recording        distance, time, average; Pause and Finish
///   Paused           the same, greyed; Resume and Finish
///   Save this ride?  a name, Save ride, Throw it away   (FinishCards.swift)
///   Too short        Keep riding, Throw it away
///   Saved / Kept on this phone / Not kept, once Save has been pressed
struct RecordTab: View {
    @Environment(Store.self) private var store

    var body: some View {
        let outcome = store.ride(store.shown)
        let ride = store.current ?? outcome
        VStack(spacing: 0) {
            RideMap(points: ride?.points ?? [],
                    follow: !store.demo && (ride == nil || ride?.status == .recording))
            card(current: store.current, outcome: outcome)
        }
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .animation(.default, value: store.current?.status)
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
        } else if store.recorder.refused {
            LocationOffCard()
        } else {
            ReadyCard()
        }
    }
}

/// The map: where the phone is, and the line ridden so far.
struct RideMap: View {
    let points: [Point]
    /// Keep the phone's position in the middle, or show the whole line.
    let follow: Bool

    private static let tallinn = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 59.437, longitude: 24.7536),
        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.12))

    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(RideMap.tallinn))

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
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
    }

    private func aim() {
        if follow {
            camera = .userLocation(fallback: .region(Self.tallinn))
        } else if points.count > 1 {
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
    var body: some View {
        SheetCard {
            Text(L.t("locOffTitle")).font(.title2.bold()).foregroundStyle(Theme.ink)
            Note(text: L.t("locOffWhy")).padding(.top, 4).padding(.bottom, 14)
            Button(L.t("openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.big)
        }
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
            .padding(.bottom, 14)

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
