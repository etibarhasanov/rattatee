import SwiftUI

/// Rattatee: record a bike ride in Tallinn with the phone in your pocket.
///
/// "Rattatee" is Estonian for a bike path. The app's one job is to record a
/// ride with the screen off and save it to Tallinn Tastebuds, where the rides
/// are collected to become a map of confirmed bike routes. The website
/// records rides too, but a web page stops hearing where it is when the
/// screen locks; `Core/Recorder.swift` says how an app does not.
///
/// It has no server: `Core/API.swift` says what it asks the website for.
/// Nobody has to sign in; an account, for whoever wants one, is the
/// website's, as in Kohuke, which this app's structure, sign-in and
/// networking are copied from.
@main
struct RattateeApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task {
                    #if DEBUG
                    LaunchScript.stage(store)
                    #endif
                    // The copy of the website's places a phone kept until
                    // 2026-11-18, which nothing reads now (WHY THE PHONE
                    // KEEPS NO COPY OF THE PLACES in Views/SearchSheet.swift).
                    try? FileManager.default.removeItem(at: Disk.support.appendingPathComponent("venues.json"))
                    await store.whoAmI()
                }
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .active:
                // Coming back is when a waiting ride might go: whoAmI() ends
                // by sending whatever is waiting.
                Task { await store.whoAmI() }
            case .background:
                // Recording carries on back there; this only makes sure the
                // points since the last write are on disk before it does.
                store.keepCurrent()
            default:
                break
            }
        }
    }
}

/// The three tabs. The app opens on Record: there is no first screen and no
/// sign-in in the way of a ride.
struct RootView: View {
    @State private var tab = LaunchScript.tab

    var body: some View {
        TabView(selection: $tab) {
            RecordTab()
                .tabItem { Label(L.t("tabRecord"), systemImage: "record.circle") }
                .tag(0)
            RidesTab()
                .tabItem { Label(L.t("tabRides"), systemImage: "list.bullet") }
                .tag(1)
            AccountTab()
                .tabItem { Label(L.t("tabAccount"), systemImage: "person.crop.circle") }
                .tag(2)
        }
        // The colour chosen under Account on every control, and the
        // background: the phone's own, or Light or Dark whatever it says.
        .tint(Theme.accent)
        .preferredColorScheme(StyleStore.shared.look.scheme)
    }
}
