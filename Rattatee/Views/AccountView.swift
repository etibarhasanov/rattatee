import SwiftUI

/// The Account tab: making an account or signing in — with a username and a
/// password, or Apple or Google — which nobody has to do; signing out and
/// deleting the account; the language; the colour and the background; and
/// the privacy page.
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
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(L.t("tabAccount"))
            .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
    }
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
