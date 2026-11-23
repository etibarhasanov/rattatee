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
/// The map on the page is the ride framed and still, so the page scrolls
/// under a thumb on it, and a tap opens it over the whole screen
/// (`RideMapCover`). The speed and the kilometres are drawn as on the map
/// app's ride page, in this app's colours.
///
/// A MAP THAT CANNOT MOVE ZOOMS ON ITS MIDDLE
///
/// Until 2026-11-21 the map on the page was the map app's: zoom only, so the
/// page scrolled under the thumb. But a map that cannot be moved zooms on
/// its middle, wherever the fingers are, so the middle of a ride was the
/// only part of it that could be looked at closely, as the owner found.
/// Letting it move on the page would have had a thumb on it move the map
/// and not the page, so it opens instead, and over the whole screen it moves
/// and zooms as any map does.
///
/// A PART OPENS ITS OWN MAP
///
/// The owner asked on 2026-11-22 for Part by part to show where each part
/// was. The page's map cannot: by the time the list is on the screen it has
/// scrolled away above it. So a tap on a part opens a still map under its
/// row, framed to that part — riding bold over the rest of the ride drawn
/// faint, a wait or a stop a ringed dot where the rider stood — and a tap
/// on that map opens it over the whole screen, framed the same. One part is
/// open at a time, and a tap on its row again puts it away.
struct RideView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: String

    @State private var kept: Kept?
    @State private var removing = false
    /// The map open over the whole screen. CI's `-kMap YES` starts with it
    /// open, so it can be photographed.
    @State private var mapping: Bool = {
        #if DEBUG
        if LaunchScript.map { return true }
        #endif
        return false
    }()
    /// The part open under its row in Part by part, by its place in the
    /// list; nil for none.
    @State private var opened: Int?
    /// The part the map over the whole screen opened on, by its place in the
    /// list; nil for the whole ride. CI's `-kPart <n>` with `-kMap YES` opens
    /// it on that part.
    @State private var mapPart: Int? = {
        #if DEBUG
        if let n = LaunchScript.part { return n }
        #endif
        return nil
    }()

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
        let parts = Timeline.parts(of: ride)
        let stops: [CLLocationCoordinate2D] = parts.compactMap { $0.kind == .stop ? $0.at : nil }
        let line = keptLine
        let whole = Self.frame(ride.points + (ride.aside ?? []).flatMap { $0 })
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

                map(ride, line: line, stops: stops, part: nil, frame: whole, height: 260)
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

                // The session, part by part. A ride that was only riding is
                // one part, and a list of one says nothing the numbers
                // above have not.
                if parts.count > 1 {
                    VStack(alignment: .leading, spacing: 0) {
                        heading(L.t("rideParts")).padding(.bottom, 8)
                        timeline(parts, ride: ride, line: line, stops: stops)
                    }
                    .padding(16)
                    .ridePanel()
                }

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
        // What the page has, line and all: opening it asks for nothing.
        .fullScreenCover(isPresented: $mapping) {
            RideMapCover(ride: ride, line: line, stops: stops, whole: whole,
                         part: mapPart.flatMap { parts.indices.contains($0) ? parts[$0] : nil })
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

    /// The website's line for this ride, where it has said; empty until
    /// then, and for a ride it does not keep.
    private var keptLine: [CLLocationCoordinate2D] {
        kept?.line.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil } ?? []
    }

    /// A map on the page, still, so a thumb on it scrolls the page — and a
    /// tap anywhere on it opens it over the whole screen, which the sign in
    /// its corner says. The whole ride at the top of the page, with `part`
    /// nil; under an open row of Part by part, that part, by its place in
    /// the list, and the map over the whole screen opens on it too.
    private func map(_ ride: Ride, line: [CLLocationCoordinate2D], stops: [CLLocationCoordinate2D],
                     part: (Int, Part)?, frame: MKMapRect, height: CGFloat) -> some View {
        Map(initialPosition: .rect(frame), interactionModes: []) {
            Self.marks(ride, line: line, stops: stops, part: part?.1)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                .padding(8)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        .onTapGesture { cover(part?.0) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("rideMapOpen"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { cover(part?.0) }
    }

    /// Opens the map over the whole screen, on the part at `index` or on
    /// the whole ride.
    private func cover(_ index: Int?) {
        mapPart = index
        mapping = true
    }

    /// What a ride's map draws, on the page and over the whole screen alike.
    /// A walk is dotted and a train dashed, both in the muted colour; a stop
    /// is a small muted dot where the rider stood; the phone's line goes
    /// faint under the website's where there is one; a ring where the ride
    /// began and a dot where it ended.
    ///
    /// With a `part`, all of that is faint and the part is drawn over it:
    /// riding bold in the ride's colour, a walk or a train bold in the ink
    /// with its own dots or dashes, and a wait or a stop a larger dot in a
    /// ring where the rider stood.
    @MapContentBuilder
    fileprivate static func marks(_ ride: Ride, line: [CLLocationCoordinate2D],
                                  stops: [CLLocationCoordinate2D], part: Part? = nil) -> some MapContent {
        let aside = ride.aside ?? []
        let rest = part == nil ? 1.0 : 0.3
        ForEach(Array(aside.enumerated()), id: \.offset) { k, stretch in
            if stretch.count > 1 {
                MapPolyline(coordinates: stretch.map(\.coordinate))
                    .stroke(Theme.muted.opacity(rest),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: Self.dash(ride.asideKind(k))))
            }
        }
        ForEach(Array(stops.enumerated()), id: \.offset) { _, at in
            Annotation("", coordinate: at) {
                Circle().fill(Theme.muted).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .opacity(rest)
            }
        }
        // The phone's line, faint once the website's is over it.
        ForEach(Array(Geo.runs(ride.points, around: aside).enumerated()), id: \.offset) { _, run in
            if run.count > 1 {
                MapPolyline(coordinates: run.map(\.coordinate))
                    .stroke(Theme.here.opacity((line.isEmpty ? 1 : 0.35) * rest),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        if line.count > 1 {
            MapPolyline(coordinates: line)
                .stroke(Theme.here.opacity(rest), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        if let first = ride.points.first {
            Annotation("", coordinate: first.coordinate) {
                Circle().fill(.white).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.here, lineWidth: 3))
                    .opacity(part == nil ? 1 : 0.5)
            }
        }
        if let last = ride.points.last {
            Annotation("", coordinate: last.coordinate) {
                Circle().fill(Theme.here).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .opacity(part == nil ? 1 : 0.5)
            }
        }
        if let part {
            let shown = Timeline.points(of: part, in: ride).map(\.coordinate)
            let stood = part.kind == .wait || part.kind == .stop
            if !stood && shown.count > 1 {
                MapPolyline(coordinates: shown)
                    .stroke(Theme.paper.opacity(0.6), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: shown)
                    .stroke(part.kind == .ride ? Theme.here : Theme.ink,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round, dash: Self.dash(part.kind)))
            }
            if stood, let at = shown.first {
                Annotation("", coordinate: at) {
                    Circle().fill(Theme.here.opacity(0.18)).frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Theme.here.opacity(0.5), lineWidth: 1.5))
                        .overlay(Circle().fill(Theme.muted).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 2.5)))
                }
            }
        }
    }

    /// A walk is dotted, a train or a drive dashed, and riding solid.
    private static func dash(_ kind: Part.Kind) -> [CGFloat] {
        switch kind {
        case .walk: return [1, 8]
        case .vehicle: return [10, 8]
        default: return []
        }
    }

    /// The box round the ride, or round a part of it, with a margin so its
    /// ends are not on the edge; a part that stood still, a box about 400 m
    /// across round where it stood.
    fileprivate static func frame(_ points: [Point]) -> MKMapRect {
        let rect = points.reduce(MKMapRect.null) { box, p in
            box.union(MKMapRect(origin: MKMapPoint(p.coordinate), size: MKMapSize(width: 1, height: 1)))
        }
        guard !rect.isNull else {
            let middle = MKMapPoint(CLLocationCoordinate2D(latitude: 59.437, longitude: 24.7536))
            return MKMapRect(x: middle.x - 5000, y: middle.y - 5000, width: 10000, height: 10000)
        }
        // Never closer than 400 m across — the box is in map points, some
        // thirteen to the metre here — so a part that stood still is framed
        // with the streets round it rather than the dot alone.
        let least = 400 * MKMapPointsPerMeterAtLatitude(points[0].lat)
        let pad = max(rect.width, rect.height) * 0.15 + 200 + max(0, least - max(rect.width, rect.height)) / 2
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    // MARK: Part by part

    /// What happened, in order: a sign and a word for what it was, when it
    /// began, and how far and how long — with the speed for the parts that
    /// moved. Riding is in the app's colour and everything else muted, so
    /// the eye finds the riding first; the word says which, never the
    /// colour alone.
    ///
    /// Each row is a button: a tap opens the part's own map under it and
    /// puts away the one open before, and a tap again puts it away. The
    /// chevron turns down on the open one and its word takes the ride's
    /// colour.
    private func timeline(_ parts: [Part], ride: Ride, line: [CLLocationCoordinate2D],
                          stops: [CLLocationCoordinate2D]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { k, part in
                let isOpen = opened == k
                Button {
                    withAnimation(.snappy) { opened = isOpen ? nil : k }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: Self.sign(part.kind))
                            .font(.subheadline)
                            .foregroundStyle(part.kind == .ride ? Theme.here : Theme.muted)
                            .frame(width: 26, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.word(part.kind)).font(.subheadline.weight(.medium))
                                .foregroundStyle(isOpen ? Theme.here : Theme.ink)
                            Text(L.time(Date(timeIntervalSince1970: part.from)))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        Text(Self.figures(part))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(L.t("partShow"))
                .accessibilityAddTraits(isOpen ? .isSelected : [])
                if isOpen {
                    map(ride, line: line, stops: stops, part: (k, part),
                        frame: Self.frame(Timeline.points(of: part, in: ride)), height: 180)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
                if k != parts.count - 1 { Divider().overlay(Theme.hairline) }
            }
        }
    }

    private static func sign(_ kind: Part.Kind) -> String {
        switch kind {
        case .ride: return "bicycle"
        case .walk: return "figure.walk"
        case .vehicle: return "tram.fill"
        case .wait: return "hourglass"
        case .stop: return "mappin.and.ellipse"
        }
    }

    private static func word(_ kind: Part.Kind) -> String {
        switch kind {
        case .ride: return L.t("partRide")
        case .walk: return L.t("partWalk")
        case .vehicle: return L.t("partVehicle")
        case .wait: return L.t("partWait")
        case .stop: return L.t("partStop")
        }
    }

    /// "1.9 km · 9:31 · 12.0 km/h" for a part that moved, "13:02" for one
    /// that stood.
    private static func figures(_ part: Part) -> String {
        let time = L.clock(Int(part.seconds.rounded()))
        guard part.metres > 0, part.seconds > 0 else { return time }
        let kmh = part.metres / part.seconds * 3.6
        return "\(L.distance(part.metres)) · \(time) · \(String(format: "%.1f", kmh)) km/h"
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

/// A ride's map over the whole screen, opened by a tap on the one on its
/// page: the same lines and dots, framed to the whole ride at first, then
/// moved and zoomed as any map is, anywhere along it. **Whole ride** frames
/// it again once it has been moved, and is greyed until then.
///
/// Opened from a part's own map, it is framed to that part and draws it as
/// that map does, bold over the rest; **Whole ride** frames the whole ride
/// with the part still bold, and is not greyed until it has.
///
/// Everything on it is what the page already had, the website's line too,
/// so opening it asks the website for nothing; the map is Apple's.
private struct RideMapCover: View {
    let ride: Ride
    let line: [CLLocationCoordinate2D]
    let stops: [CLLocationCoordinate2D]
    /// The box round the ride, as the page's map is framed.
    let whole: MKMapRect
    /// The part it opened on, or nil for the whole ride.
    let part: Part?

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    /// Still framed to the part it opened on, which **Whole ride** undoes.
    @State private var onPart: Bool

    init(ride: Ride, line: [CLLocationCoordinate2D], stops: [CLLocationCoordinate2D], whole: MKMapRect,
         part: Part?) {
        self.ride = ride
        self.line = line
        self.stops = stops
        self.whole = whole
        self.part = part
        _position = State(initialValue: .rect(part.map { RideView.frame(Timeline.points(of: $0, in: ride)) } ?? whole))
        _onPart = State(initialValue: part != nil)
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                RideView.marks(ride, line: line, stops: stops, part: part)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .navigationTitle(ride.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.t("rideMapWhole")) {
                        onPart = false
                        withAnimation { position = .rect(whole) }
                    }
                    .disabled(!onPart && !position.positionedByUser)
                }
                ToolbarItem(placement: .topBarTrailing) { Button(L.t("close")) { dismiss() } }
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
