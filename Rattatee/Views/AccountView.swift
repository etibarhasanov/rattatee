import SwiftUI

/// The Account tab: making an account or signing in — with a username and a
/// password, or Apple or Google — which nobody has to do; signing out and
/// deleting the account; the language; the colour and the background; the
/// privacy page; and, at the foot, which version and build this is. What the
/// account's rides add up to is on My rides,
/// under All on the card at the top (`StatsCard`).
struct AccountTab: View {
    @Environment(Store.self) private var store
    @State private var deleting = false

    var body: some View {
        @Bindable var style = StyleStore.shared
        @Bindable var lang = LangStore.shared
        NavigationStack {
            Form {
                if let user = store.user {
                    Section {
                        Text(L.t("accountSignedIn", ["name": user])).foregroundStyle(Theme.ink)
                        Button(L.t("accountSignOut")) { Task { await store.signOut() } }
                        Button(L.t("accountDelete"), role: .destructive) { deleting = true }
                    }
                    .listRowBackground(Theme.card)
                } else {
                    PasswordForm()
                    if store.appleOffered || store.googleOffered {
                        Section {
                            SignInDoors()
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        } header: {
                            Text(L.t("accountOr")).textCase(nil).frame(maxWidth: .infinity)
                        }
                    }
                }

                // The app's own language, whatever the phone's is. The names
                // are each in their own language, as every language menu is.
                Section {
                    Picker(L.t("language"), selection: $lang.choice) {
                        Text(L.t("languagePhone")).tag("")
                        Text("English").tag("en")
                        Text("Eesti").tag("et")
                        Text("Русский").tag("ru")
                        Text("Azərbaycanca").tag("az")
                    }
                    .foregroundStyle(Theme.ink)
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack {
                        ForEach(Hue.allCases) { hue in
                            HueSwatch(hue: hue, chosen: style.hue == hue) { style.hue = hue }
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                    Picker(L.t("lookBackground"), selection: $style.look) {
                        Text(L.t("lookPhone")).tag(Look.phone)
                        Text(L.t("lookLight")).tag(Look.light)
                        Text(L.t("lookDark")).tag(Look.dark)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                } header: {
                    Text(L.t("lookTitle"))
                }
                .listRowBackground(Theme.card)

                Section {
                    Link(L.t("privacyLink"), destination: API.privacy)
                } footer: {
                    // Which build this is, for somebody telling the owner
                    // what went wrong: the builds of one version on
                    // TestFlight are told apart by the number in brackets.
                    Text(L.t("version", ["version": Self.version]))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .textSelection(.enabled)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(L.t("tabAccount"))
            .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
    }

    /// The version people see and the build, "1.0 (142)", read from the app
    /// itself: a tag sets the first and the package workflow the second
    /// (docs/RELEASING.md), so nothing here changes for a release.
    private static let version: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let shown = info["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info["CFBundleVersion"] as? String else { return shown }
        return "\(shown) (\(build))"
    }()
}

/// One colour to choose: a dot in its daytime accent, ringed when chosen,
/// with its name under it.
private struct HueSwatch: View {
    let hue: Hue
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(UIColor(hex: Palette.of(hue, dark: false).accent)))
                    .frame(width: 32, height: 32)
                    .overlay { if chosen { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                    .padding(3)
                    .overlay(Circle().stroke(chosen ? Theme.ink : .clear, lineWidth: 2))
                Text(hue.name).font(.caption).foregroundStyle(chosen ? Theme.ink : Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Deleting the account, which App Review asks every app that makes accounts
/// to offer from inside the app. Kohuke's, to the letter: the account is the
/// website's, so what goes is everything under that name there, and the site
/// asks for the password again, or, for an account made with Apple or Google
/// and no password, the username typed out. The rides on this phone stay on
/// this phone.
struct DeleteAccountView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var working = false
    @State private var problem = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L.t("accountDeleteWhy", ["name": store.user ?? ""]))
                    Text(L.t("accountDeleteCosts")).foregroundStyle(Theme.muted)
                }
                Section {
                    SecureField(L.t("accountCurrentPassword"), text: $confirmation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(L.t("appDeleteNoPassword"))
                }
                Section {
                    Button(role: .destructive) {
                        working = true
                        problem = false
                        Task {
                            defer { working = false }
                            do {
                                try await store.deleteAccount(confirmation: confirmation)
                                dismiss()
                            } catch {
                                problem = true
                            }
                        }
                    } label: {
                        Text(L.t("accountDeleteGo")).fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .disabled(confirmation.isEmpty || working)
                } footer: {
                    if problem { Text(L.t("signInProblem")).foregroundStyle(Theme.bad) }
                }
            }
            .navigationTitle(L.t("accountDelete"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(L.t("close")) { dismiss() } }
            }
        }
    }
}
