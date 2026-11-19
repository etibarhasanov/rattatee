import MapKit
import SwiftUI

/// The map: where the phone is, and the line ridden so far. A tap on it is
/// somewhere to go, before a ride or during one with nowhere to go yet: a place Apple's map names, or anywhere.
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
///
/// WHY IT IS AN MKMapView
///
/// It was SwiftUI's `Map` until 2026-11-19, and SwiftUI's `Map` draws
/// Apple's map and nothing over it but lines and pins. The bike paths are
/// pictures from somebody else's server — `BikePaths` below — and only
/// `MKMapView` takes those. So the map is `MapCanvas`, an `MKMapView`
/// wrapped, and everything the old one did is done there by hand: the
/// lines, the pin, the tap, the camera.
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
    /// and the point. Nil when taps do nothing: on the save card, and
    /// while riding to somewhere already chosen.
    var tap: ((String?, CLLocationCoordinate2D) -> Void)?

    /// Whether the bike paths are drawn. Off until the rider asks, and
    /// remembered: see `BikePaths` for what on costs.
    @AppStorage("bikePaths") private var bikePaths = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MapCanvas(lines: lines, goal: goal, here: here, follow: follow, whole: points.count > 1,
                  bikePaths: bikePaths,
                  // The lines are coloured when they are made, so a change
                  // of colour or of light and dark has to make them again.
                  look: StyleStore.shared.hue.rawValue + (scheme == .dark ? "-dark" : "-light"),
                  tap: tap)
            // Above Apple's "Legal", which keeps the corner.
            .overlay(alignment: .bottomTrailing) { bikeButton.padding(.trailing, 8).padding(.bottom, 30) }
            // And above Apple's mark, short of the button.
            .overlay(alignment: .bottomLeading) {
                if bikePaths { credit.padding(.leading, 8).padding(.bottom, 30).padding(.trailing, 64) }
            }
    }

    private var bikeButton: some View {
        Button { bikePaths.toggle() } label: {
            Image(systemName: "bicycle")
                .font(.body.weight(.semibold))
                .foregroundStyle(bikePaths ? Theme.onAccent : Theme.ink)
                .frame(width: 44, height: 44)
                .background(bikePaths ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .accessibilityLabel(L.t("mapBikePaths"))
        .accessibilityAddTraits(bikePaths ? .isSelected : [])
    }

    /// Whose the bike paths are, which their owners ask to be said on the
    /// map while it shows them, with the way to OpenStreetMap's licence.
    private var credit: some View {
        Link(destination: BikePaths.licence) {
            Text(BikePaths.credit)
                .font(.caption2)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.card.opacity(0.85), in: Capsule())
        }
    }

    /// Everything drawn as a line, the bottom one first.
    private var lines: [MapLine] {
        var all: [MapLine] = []
        if let goal {
            if case .found(let way) = goal.way {
                // The ways on offer and not chosen, faint under the one
                // that is, while it is still a choice: before a ride, and
                // just after a new way mid-ride until the rider has ridden
                // onto one (`Store.pick`).
                if points.isEmpty || goal.picking != nil {
                    for (k, other) in goal.ways.enumerated() where k != goal.chosen {
                        all.append(MapLine(coordinates: other.line, kind: .other))
                    }
                }
                if let train = way.train {
                    // A way by train: the rides solid, as any way, and the
                    // rail dashed, so it is not read as a road.
                    for leg in train.legs { all.append(MapLine(coordinates: leg.line, kind: leg.bike ? .way : .rail)) }
                } else {
                    all.append(MapLine(coordinates: way.line, kind: .way))
                }
            } else if goal.way == .looking, points.isEmpty, let here {
                // As the crow flies, until the website says how a bike
                // goes. Dotted, so it is not read as a way to ride.
                all.append(MapLine(coordinates: [here, goal.spot.coordinate], kind: .crow))
            }
        }
        for stretch in aside where stretch.count > 1 {
            all.append(MapLine(coordinates: stretch.map(\.coordinate), kind: .aside))
        }
        for run in Geo.runs(points, around: aside) where run.count > 1 {
            all.append(MapLine(coordinates: run.map(\.coordinate), kind: .ridden))
        }
        return all
    }
}

/// One line on the map and what it is, which is how it is drawn.
struct MapLine {
    enum Kind: Int {
        /// A way on offer and not chosen; the way; its stretch by rail; the
        /// straight line before there is a way; a stretch set aside; the
        /// line ridden.
        case other, way, rail, crow, aside, ridden
    }

    let coordinates: [CLLocationCoordinate2D]
    let kind: Kind

    /// The same number for the same line drawn the same way, so a line
    /// that has not changed is left on the map and not drawn again.
    func mark(_ look: String) -> Int {
        var hasher = Hasher()
        hasher.combine(look)
        hasher.combine(kind)
        hasher.combine(coordinates.count)
        for point in coordinates {
            hasher.combine(point.latitude)
            hasher.combine(point.longitude)
        }
        return hasher.finalize()
    }
}

/// The bike paths: OpenStreetMap's cycle tracks, lanes and shared paths,
/// drawn by CyclOSM as see-through pictures that lie over Apple's map —
/// its `cyclosm-lite` layer, which is the paths and nothing else.
///
/// WHAT IT COSTS, AND WHOM
///
/// Nothing of the website's: the pictures come from OpenStreetMap France's
/// servers, which volunteers pay for, so they are asked as little as a map
/// can ask:
///
/// - Only when the rider has switched them on — the bicycle button on the
///   map — which a new install has not.
/// - Only for what is on the screen, and never from zoomed out further than
///   a district (`closest`), where a path is thinner than a pixel anyway.
/// - Once: a picture is kept on the phone for as long as the server says it
///   may be, `kept` megabytes of them, and a street ridden twice is asked
///   for once.
/// - Two at a time, which is what OpenStreetMap asks of an app.
/// - With the app's name on the request, so its owners can tell who is
///   asking and say so if it is too much.
/// - A picture that fails is not asked for again until the map next needs
///   that square; MapKit does not retry by itself.
///
/// How often: a screen is about a dozen pictures. Riding with the map
/// following, at 17 km/h and a street-level zoom, a new row of four comes
/// into view every minute or so — some two hundred an hour the first time
/// along a street, and none the second. With the screen off the map is not
/// drawn and nothing is asked.
///
/// The address is as CyclOSM publishes it for its lite layer. It was
/// written on 2026-11-19 from a session that could not reach it, so the
/// first build with this is the first time it was asked.
final class BikePaths: MKTileOverlay {
    static let credit = "© OpenStreetMap · CyclOSM · OSM France"
    static let licence = URL(string: "https://www.openstreetmap.org/copyright")!

    /// The furthest out the pictures are asked for, and the closest in they
    /// are drawn.
    static let furthest = 11
    static let closest = 19
    /// How many megabytes of pictures the phone keeps.
    static let kept = 64

    static func make() -> BikePaths {
        let paths = BikePaths(urlTemplate: nil)
        paths.canReplaceMapContent = false
        paths.minimumZ = furthest
        paths.maximumZ = closest
        return paths
    }

    private static let session: URLSession = {
        let settings = URLSessionConfiguration.default
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bike-paths", isDirectory: true)
        settings.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: kept << 20, directory: folder)
        settings.requestCachePolicy = .useProtocolCachePolicy
        settings.httpMaximumConnectionsPerHost = 2
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        settings.httpAdditionalHeaders = ["User-Agent": "Rattatee/\(version) (iOS; +https://tallinntastebuds.ee)"]
        return URLSession(configuration: settings)
    }()

    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        // One server of the three by the square, so the same square is
        // always the same address and is found in the cache.
        let server = ["a", "b", "c"][abs(path.x + path.y) % 3]
        return URL(string: "https://\(server).tile-cyclosm.openstreetmap.fr/cyclosm-lite/\(path.z)/\(path.x)/\(path.y).png")!
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        Self.session.dataTask(with: url(forTilePath: path)) { data, response, error in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else {
                result(nil, error ?? URLError(.badServerResponse))
                return
            }
            result(data, nil)
        }.resume()
    }
}

/// A line on the `MKMapView`, which remembers what kind it is.
private final class Stroke: MKPolyline {
    var kind = MapLine.Kind.way
}

/// An `MKMapView` that says when it first has a size, which is the first
/// moment a frame can be set on it.
private final class SizedMap: MKMapView {
    var sized: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, bounds.height > 0, let sized {
            self.sized = nil
            sized()
        }
    }
}

/// The `MKMapView` under `RideMap`. It is told what to draw and where the
/// rider is going, and `Coordinator` makes the map agree with that each
/// time any of it changes.
private struct MapCanvas: UIViewRepresentable {
    let lines: [MapLine]
    let goal: Goal?
    let here: CLLocationCoordinate2D?
    let follow: Bool
    /// Whether there is a line ridden to show the whole of, when the map
    /// is not following.
    let whole: Bool
    let bikePaths: Bool
    let look: String
    let tap: ((String?, CLLocationCoordinate2D) -> Void)?

    static let tallinn = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 59.437, longitude: 24.7536),
        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.12))

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = SizedMap()
        let coordinator = context.coordinator
        map.sized = { [weak map, weak coordinator] in
            if let map, let coordinator { coordinator.aim(map, animated: false) }
        }
        map.delegate = coordinator
        map.showsUserLocation = true
        // Tallinn until the phone says where it is.
        map.setRegion(Self.tallinn, animated: false)

        // The locate button and the compass, where SwiftUI's map had them:
        // the top right corner, which Where to? stops short of.
        map.showsCompass = false
        let locate = MKUserTrackingButton(mapView: map)
        locate.layer.cornerRadius = 8
        locate.layer.masksToBounds = true
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        for control in [locate, compass] {
            control.translatesAutoresizingMaskIntoConstraints = false
            map.addSubview(control)
        }
        NSLayoutConstraint.activate([
            locate.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 10),
            locate.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            locate.widthAnchor.constraint(equalToConstant: 44),
            locate.heightAnchor.constraint(equalToConstant: 44),
            compass.topAnchor.constraint(equalTo: locate.bottomAnchor, constant: 10),
            compass.centerXAnchor.constraint(equalTo: locate.centerXAnchor)
        ])
        context.coordinator.locate = locate

        // Beside the map's own gestures rather than instead of them:
        // dragging and pinching go on as before.
        let finger = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        finger.delegate = context.coordinator
        map.addGestureRecognizer(finger)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.canvas = self
        context.coordinator.agree(map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var canvas: MapCanvas
        weak var locate: MKUserTrackingButton?

        /// What is on the map now: the lines by their marks, bottom first,
        /// the bike paths, and the pin.
        private var drawn: [(mark: Int, stroke: Stroke)] = []
        private var paths: BikePaths?
        private var pin: MKPointAnnotation?
        private var look = ""

        /// What the camera last answered to, so it moves on a change and
        /// not on every redraw. Nil before the first.
        private var follow: Bool?
        private var goalID: String?
        private var looking = false

        /// When the map last selected a place it drew, so the tap under it
        /// does not drop a pin as well.
        private var pickedAt = Date.distantPast

        init(_ canvas: MapCanvas) { self.canvas = canvas }

        // MARK: What is drawn

        func agree(_ map: MKMapView) {
            // The bike paths, under every line.
            if canvas.bikePaths, paths == nil {
                let new = BikePaths.make()
                map.insertOverlay(new, at: 0, level: .aboveRoads)
                paths = new
            } else if !canvas.bikePaths, let old = paths {
                map.removeOverlay(old)
                paths = nil
            }

            // The lines. One that has not changed stays; from the first
            // that has, the new are put on before the old come off, so the
            // line being ridden does not blink each time it grows.
            let marks = canvas.lines.map { $0.mark(canvas.look) }
            if marks != drawn.map(\.mark) {
                var same = 0
                while same < marks.count, same < drawn.count, marks[same] == drawn[same].mark { same += 1 }
                let old = drawn[same...].map(\.stroke)
                drawn.removeSubrange(same...)
                for (line, mark) in zip(canvas.lines, marks).dropFirst(same) {
                    let stroke = Stroke(coordinates: line.coordinates, count: line.coordinates.count)
                    stroke.kind = line.kind
                    map.addOverlay(stroke, level: .aboveRoads)
                    drawn.append((mark, stroke))
                }
                map.removeOverlays(old)
            }

            // The pin: there with somewhere to go, and moved or renamed in
            // place — a pin's street arriving is not a new pin.
            if let goal = canvas.goal {
                let pin = self.pin ?? MKPointAnnotation()
                if pin.title != goal.spot.name { pin.title = goal.spot.name }
                if pin.coordinate.latitude != goal.spot.lat || pin.coordinate.longitude != goal.spot.lng {
                    pin.coordinate = goal.spot.coordinate
                }
                if self.pin == nil {
                    map.addAnnotation(pin)
                    self.pin = pin
                }
            } else if let pin {
                map.removeAnnotation(pin)
                self.pin = nil
            }

            // The colours of what is not a line.
            if look != canvas.look {
                look = canvas.look
                locate?.tintColor = colour(Theme.accent, in: map)
                locate?.backgroundColor = colour(Theme.card, in: map)
                if let pin { (map.view(for: pin) as? MKMarkerAnnotationView)?.markerTintColor = colour(Theme.accent, in: map) }
            }

            // A place Apple's map names can be chosen where a tap can.
            let features: MKMapFeatureOptions = canvas.tap == nil ? [] : .pointsOfInterest
            if map.selectableMapFeatures != features { map.selectableMapFeatures = features }

            camera(map)
        }

        private func colour(_ colour: Color, in map: MKMapView) -> UIColor {
            UIColor(colour).resolvedColor(with: map.traitCollection)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let paths = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: paths) }
            guard let stroke = overlay as? Stroke else { return MKOverlayRenderer(overlay: overlay) }
            let line = MKPolylineRenderer(polyline: stroke)
            line.lineCap = .round
            line.lineJoin = .round
            let accent = colour(Theme.accent, in: mapView)
            switch stroke.kind {
            case .other:
                line.strokeColor = accent.withAlphaComponent(0.3)
                line.lineWidth = 4
            case .way:
                line.strokeColor = accent.withAlphaComponent(0.75)
                line.lineWidth = 5
            case .rail:
                line.strokeColor = accent.withAlphaComponent(0.75)
                line.lineWidth = 5
                line.lineDashPattern = [8, 8]
            case .crow:
                line.strokeColor = accent.withAlphaComponent(0.6)
                line.lineWidth = 4
                line.lineDashPattern = [1, 9]
            case .aside:
                line.strokeColor = colour(Theme.muted, in: mapView)
                line.lineWidth = 4
                line.lineDashPattern = [1, 8]
            case .ridden:
                line.strokeColor = colour(Theme.here, in: mapView)
                line.lineWidth = 5
            }
            return line
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // The rider's dot and the places Apple draws are the map's own.
            guard let pin, annotation === pin else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "goal") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "goal")
            view.annotation = annotation
            view.markerTintColor = colour(Theme.accent, in: mapView)
            view.displayPriority = .required
            return view
        }

        // MARK: The camera

        private func camera(_ map: MKMapView) {
            let goal = canvas.goal
            let nowLooking = goal?.way == .looking
            defer {
                follow = canvas.follow
                goalID = goal?.spot.id
                looking = nowLooking
            }
            // The first time the map has no size yet, and a frame set now
            // is a frame of nothing: `SizedMap` aims it when it has one.
            guard let was = follow else { return }
            // Choosing somewhere to go stops the following and moves
            // nothing; letting it go, or starting to ride, takes the
            // camera back.
            if was != canvas.follow {
                if canvas.follow || goal == nil {
                    aim(map, animated: true)
                } else if map.userTrackingMode != .none {
                    map.setUserTrackingMode(.none, animated: false)
                }
            }
            guard !canvas.follow, let goal else { return }
            // By the place and by the way, never by the goal whole: a pin's
            // street arriving is a change to the goal and no reason to move.
            if goalID != goal.spot.id {
                // Off the screen, or arriving with its way already found (a
                // staged screen does): there is no later moment to frame it at.
                if !inView(goal.spot.coordinate, map) || goal.way != .looking { settle(goal, map) }
            } else if looking != nowLooking, goal.way != .looking {
                // And not by which way is chosen: all of them are in the frame.
                settle(goal, map)
            }
        }

        func aim(_ map: MKMapView, animated: Bool) {
            if canvas.follow {
                map.setUserTrackingMode(.follow, animated: animated)
            } else if canvas.whole {
                // Everything drawn: the line, the way, the destination.
                var rect = drawn.reduce(MKMapRect.null) { $0.union($1.stroke.boundingMapRect) }
                if let pin { rect = rect.union(MKMapRect(origin: MKMapPoint(pin.coordinate), size: MKMapSize(width: 1, height: 1))) }
                guard !rect.isNull else { return }
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 72, left: 32, bottom: 40, right: 32), animated: animated)
            } else if let goal = canvas.goal {
                settle(goal, map, animated: animated)
            }
        }

        /// Whether a point is on the screen.
        private func inView(_ at: CLLocationCoordinate2D, _ map: MKMapView) -> Bool {
            let seen = map.region
            return abs(at.latitude - seen.center.latitude) < seen.span.latitudeDelta / 2
                && abs(at.longitude - seen.center.longitude) < seen.span.longitudeDelta / 2
        }

        /// Show the whole of somewhere to go: the rider, the place, and the
        /// way between them where there is one. Framed by hand, so the
        /// rider's own dot is counted.
        private func settle(_ goal: Goal, _ map: MKMapView, animated: Bool = true) {
            var all = [goal.spot.coordinate]
            if let here = canvas.here { all.append(here) }
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
            if map.userTrackingMode != .none { map.setUserTrackingMode(.none, animated: false) }
            map.setVisibleMapRect(rect, animated: animated)
        }

        // MARK: A tap

        @objc func tapped(_ finger: UITapGestureRecognizer) {
            guard canvas.tap != nil, let map = finger.view as? MKMapView else { return }
            let point = map.convert(finger.location(in: map), toCoordinateFrom: map)
            Task { @MainActor in
                // A tap on a named place selects it a moment later; wait
                // for that, and drop a pin only if it did not.
                try? await Task.sleep(for: .milliseconds(250))
                guard Date().timeIntervalSince(self.pickedAt) > 0.6 else { return }
                self.canvas.tap?(nil, point)
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard annotation is MKMapFeatureAnnotation else { return }
            pickedAt = Date()
            canvas.tap?(annotation.title ?? nil, annotation.coordinate)
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Not on the locate button or the compass, which a tap is for
        /// themselves and not a pin as well.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let under = view {
                if under is UIControl { return false }
                view = under.superview
            }
            return true
        }
    }
}
