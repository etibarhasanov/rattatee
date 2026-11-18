import SwiftUI
import MapKit
import Charts

/// One ride, opened from My rides: where it went, its numbers, and — from
/// its points — each kilometre's time and the speed along the way.
///
/// Everything on it is the phone's own ride, so it opens with no signal and
/// for a ride saved with no account, which is most of them. The numbers are
/// the save card's (`RideNumbers`); the rest is `Insight`, the website's own
/// sums run over the phone's points.
///
/// What the website has of it is drawn too, where the website will say: a
/// ride saved signed in is asked for by its id (`Kept`), and its stored line —
/// the first and last 200 m off, cut where a walk was — is drawn solid over
/// the phone's, which goes faint, so the rider sees exactly what was kept. A
/// ride saved with no account cannot be asked for, by design, and is told
/// in a sentence how much the website kept, from the answer to its save.
///
/// The map is the map app's ride page's: framed to the line, zoom only, so
/// the page scrolls under the thumb. The speed and the kilometres are drawn
/// as there too, in this app's colours.
struct RideView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String

    @State private var kept: Kept?
    @State private var removing = false

    /// Read from the store each time, so a ride that goes from Waiting to
    /// Saved while it is open says so; nil once it is removed.
    private var ride: Ride? { store.ride(id) }

    var body: some View {
        Group {
            if let ride { page(ride) }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ride?.serverId) {
            if let ride, !store.demo, store.user != nil { kept = await Kept.of(ride) }
        }
    }

    private func page(_ ride: Ride) -> some View {
        let insight = Insight(ride)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ride.title)
                        .font(.title2.bold())
                        .foregroundStyle(ride.name.isEmpty ? Theme.muted : Theme.ink)
                    HStack(spacing: 8) {
                        Text(when(ride)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.muted)
                        Spacer(minLength: 8)
                        StatusPill(ride: ride)
                    }
                }

                map(ride)
                if let note = mapNote(ride) {
                    Note(text: note).padding(.top, -4)
                }

                VStack(alignment: .leading, spacing: 0) {
                    RideNumbers(ride: ride)
                    if let insight, insight.fastest != nil || insight.stopped >= 60 {
                        Grid(alignment: .leading, horizontalSpacing: 10) {
                            GridRow {
                                Figure(value: insight.fastest.map { L.clock(Int($0.seconds)) } ?? "–",
                                       label: L.t("statFastestKm"))
                                Figure(value: L.clock(Int(insight.stopped)), label: L.t("statStopped"))
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 16)
                .ridePanel()

                if let insight, insight.speed.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        heading(L.t("rideSpeedAlong"))
                        speedChart(insight.speed)
                    }
                    .padding(16)
                    .ridePanel()
                }

                if let insight, insight.splits.count > 1 {
                    VStack(alignment: .leading, spacing: 0) {
                        heading(L.t("rideEachKm")).padding(.bottom, 8)
                        splits(insight.splits, fastest: insight.fastest?.km)
                    }
                    .padding(16)
                    .ridePanel()
                }

                // As the swipe in the list: never a ride still waiting to go.
                if ride.status != .waiting {
                    Button(L.t("rideRemove"), role: .destructive) { removing = true }
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .confirmationDialog(L.t("rideRemove"), isPresented: $removing, titleVisibility: .hidden) {
                            Button(L.t("rideRemove"), role: .destructive) {
                                store.remove(ride.id)
                                dismiss()
                            }
                        }
                }
            }
            .padding(16)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
    }

    /// Under the map: what the website has of this ride, in a sentence. Only
    /// for a saved ride; a waiting or refused one says so in its pill.
    private func mapNote(_ ride: Ride) -> String? {
        guard ride.status == .saved else { return nil }
        if let kept { return L.t("rideKeptDrawn", ["dist": L.distance(kept.meters)]) }
        if let metres = ride.serverMeters { return L.t("rideKeptMetres", ["dist": L.distance(Double(metres))]) }
        return nil
    }

    // MARK: The map

    private func map(_ ride: Ride) -> some View {
        let aside = ride.aside ?? []
        let runs = Geo.runs(ride.points, around: aside)
        let line = kept?.line.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil } ?? []
        return Map(initialPosition: .rect(Self.frame(ride.points + aside.flatMap { $0 })), interactionModes: [.zoom]) {
            ForEach(Array(aside.enumerated()), id: \.offset) { _, stretch in
                if stretch.count > 1 {
                    MapPolyline(coordinates: stretch.map(\.coordinate))
                        .stroke(Theme.muted, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
                }
            }
            // The phone's line, faint once the website's is over it.
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                if run.count > 1 {
                    MapPolyline(coordinates: run.map(\.coordinate))
                        .stroke(Theme.here.opacity(line.isEmpty ? 1 : 0.35),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            if line.count > 1 {
                MapPolyline(coordinates: line)
                    .stroke(Theme.here, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = ride.points.first {
                Annotation("", coordinate: first.coordinate) {
                    Circle().fill(.white).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.here, lineWidth: 3))
                }
            }
            if let last = ride.points.last {
                Annotation("", coordinate: last.coordinate) {
                    Circle().fill(Theme.here).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline))
    }

    /// The box round the ride, with a margin so its ends are not on the edge.
    private static func frame(_ points: [Point]) -> MKMapRect {
        let rect = points.reduce(MKMapRect.null) { box, p in
            box.union(MKMapRect(origin: MKMapPoint(p.coordinate), size: MKMapSize(width: 1, height: 1)))
        }
        guard !rect.isNull else {
            let middle = MKMapPoint(CLLocationCoordinate2D(latitude: 59.437, longitude: 24.7536))
            return MKMapRect(x: middle.x - 5000, y: middle.y - 5000, width: 10000, height: 10000)
        }
        let pad = max(rect.width, rect.height) * 0.15 + 200
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    // MARK: The speed and the kilometres

    private func speedChart(_ speed: [Insight.Speed]) -> some View {
        Chart(speed, id: \.at) { point in
            LineMark(x: .value("km", point.at / 1000), y: .value("km/h", point.kmh))
                .foregroundStyle(Theme.here)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("km", point.at / 1000), y: .value("km/h", point.kmh))
                .foregroundStyle(Theme.here.opacity(0.12))
                .interpolationMethod(.monotone)
        }
        .chartYAxisLabel("km/h")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text("\(km.formatted(.number.precision(.fractionLength(0...1)))) km").font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let kmh = value.as(Double.self) { Text(kmh.formatted(.number.precision(.fractionLength(0)))).font(.caption2) }
                }
            }
        }
        .frame(height: 160)
    }

    /// Each kilometre's time, with a bar for its speed against the ride's
    /// slowest and fastest, so the quick ones stand out without a colour;
    /// the fastest whole kilometre's bar is the full colour.
    private func splits(_ splits: [Insight.Split], fastest: Int?) -> some View {
        let speeds = splits.map(\.kmh)
        let low = (speeds.min() ?? 0) * 0.85
        let high = max(speeds.max() ?? 1, low + 1)
        return VStack(spacing: 0) {
            ForEach(splits, id: \.km) { split in
                HStack(spacing: 10) {
                    Text(String(split.km)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.muted)
                        .frame(width: 26, alignment: .leading)
                    GeometryReader { box in
                        Capsule().fill(Theme.here.opacity(split.km == fastest ? 1 : 0.6))
                            .frame(width: max(6, box.size.width * (split.kmh - low) / (high - low)), height: 8)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 20)
                    Text(L.clock(Int(split.seconds))).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink)
                        .frame(width: 52, alignment: .trailing)
                    Text(String(format: "%.1f", split.kmh)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.muted)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                if split.km != splits.last?.km { Divider().overlay(Theme.hairline) }
            }
        }
    }
}

extension View {
    /// A panel of the ride page: the card colour, rounded, with a hairline.
    fileprivate func ridePanel() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline))
    }
}
