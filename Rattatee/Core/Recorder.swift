import CoreLocation
import Foundation
import Observation

/// The phone's position, asked for over and over while a ride is recording,
/// in the background too.
///
/// THIS IS WHY THE APP EXISTS
///
/// A web page stops hearing where it is the moment the screen locks, so a
/// ride cannot be recorded from one in a pocket. An app with the `location`
/// background mode (Config/Info.plist) that starts its updates while it is on
/// screen, with `allowsBackgroundLocationUpdates` set, keeps getting them in
/// a pocket under the ordinary While Using the App permission. iOS draws the
/// blue location pill while it does, so nobody is recorded without seeing
/// it. "Always" is never asked for: nothing here wants a position when a ride
/// is not being recorded.
///
/// Updates run only between Start and Pause or Finish, and stop otherwise, so
/// a paused ride costs no battery and a locked phone with a paused ride is
/// simply asleep.
///
/// What is asked of Core Location is what a cycling app asks for: `fitness`
/// as the activity, the best accuracy there is, and never pausing on its own
/// (`pausesLocationUpdatesAutomatically` would stop a ride at a long red
/// light and not start it again until the app was opened). Which fixes are
/// good enough to keep is decided in `Store.add`, the same as the website's.
@MainActor
@Observable
final class Recorder: NSObject {
    /// A fix worse than this many metres draws the ride through the houses.
    static let sure: Double = 30

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Whether iOS gives the app the phone's real position, or the
    /// approximate one somebody can choose instead ("Precise Location" off),
    /// which is no use for drawing a ride.
    private(set) var precise = true
    private(set) var running = false
    /// Where the phone last said it was, however sure: what search measures
    /// its distances from and a suggested way starts at. Not a ride's point.
    private(set) var here: CLLocationCoordinate2D?

    /// Every fix good enough to consider, in order.
    @ObservationIgnored var onPoint: (@MainActor (Point) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    /// Start was pressed before iOS had asked the question; start once it is
    /// answered with a yes.
    @ObservationIgnored private var afterAsking: (() -> Void)?

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        precise = manager.accuracyAuthorization == .fullAccuracy
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Half the twelve metres a point needs, so a point is never missed
        // for want of a fix, without waking the app for every metre.
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
    }

    var allowed: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var refused: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Ask iOS the question, then do `then` if the answer was yes.
    func ask(then: @escaping () -> Void) {
        afterAsking = then
        manager.requestWhenInUseAuthorization()
    }

    /// One fix, for the search: where the rider is before a ride has begun.
    /// Asks the question first if iOS never has.
    func locate() {
        if allowed {
            manager.requestLocation()
        } else if !refused {
            ask { [weak self] in self?.manager.requestLocation() }
        }
    }

    func start() {
        guard allowed, !running else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        running = true
    }

    func stop() {
        guard running else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        running = false
    }
}

extension Recorder: CLLocationManagerDelegate {
    // Core Location calls back on the thread the manager was made on, which
    // is the main one, since this class is made by the Store on the main actor.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorization = manager.authorizationStatus
            precise = manager.accuracyAuthorization == .fullAccuracy
            if allowed, let then = afterAsking {
                afterAsking = nil
                then()
            } else if refused {
                afterAsking = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            if let last = locations.last, last.horizontalAccuracy >= 0 { here = last.coordinate }
            for fix in locations {
                // A negative accuracy is no fix at all.
                guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= Self.sure else { continue }
                // The height comes with the fix, above mean sea level; a
                // vertical accuracy of zero or less means there is none.
                // How sure it is decides nothing: a point is kept for where
                // it was, and its height is only ever read as a trend.
                onPoint?(Point(lat: Geo.round5(fix.coordinate.latitude),
                               lng: Geo.round5(fix.coordinate.longitude),
                               t: fix.timestamp.timeIntervalSince1970,
                               acc: (fix.horizontalAccuracy * 10).rounded() / 10,
                               alt: fix.verticalAccuracy > 0 ? (fix.altitude * 10).rounded() / 10 : nil))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // `locationUnknown` is a moment without a fix and passes by itself;
        // `denied` arrives as an authorization change as well. Nothing to do.
    }
}
