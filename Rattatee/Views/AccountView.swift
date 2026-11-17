import SwiftUI

/// Account, from the top of My rides: signing in, which nobody has to do,
/// and what it is for; signing out; deleting the account; and the link to
/// the privacy page.
struct AccountView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = store.user {
                    Section {
                        Text(L.t("accountSignedIn", ["name": user])).foregroundStyle(Theme.ink)
                        Button(L.t("accountSignOut")) { Task { await store.signOut() } }
                    }
                    Section {
                        Button(L.t("accountDelete"), role: .destructive) { deleting = true }
                    }
                } else {
                    Section {
                        SignInDoors(entered: { dismiss() })
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        Text(L.t("signInWhy")).textCase(nil)
                    } footer: {
                        Text(L.t("appSameAccount"))
                    }
                }
                Section {
                    Link(L.t("privacyLink"), destination: API.privacy)
                } footer: {
                    // Said plainly, once, where somebody looking for it would look.
                    Text(L.t("readyWhy"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(L.t("ridesAccount"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L.t("close")) { dismiss() } }
            }
            .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
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
