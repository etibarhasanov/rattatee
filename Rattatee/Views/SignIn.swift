import SwiftUI

/// The three ways in, as in Kohuke: a username and a password, and Apple and
/// Google, each of those two drawn only where the site says it can answer it
/// (`appApple` and `appGoogle` on `GET /api/account`). The same accounts as
/// the website and Kohuke. Nothing in the app needs one — a ride saves
/// without — so all of it is on the Account tab and nowhere else.
///
/// The username form came first in November 2026, at the owner's word: until
/// then a rider who wanted an account and used neither Apple nor Google had
/// to go to the website to make one.

/// Create account or Sign in, with a username and a password. One form for
/// both, switched at the top, the way the website's sheet is; the button says
/// which it will do.
struct PasswordForm: View {
    @Environment(Store.self) private var store

    @State private var creating = true
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    /// The sentence for the site's last refusal, if there was one.
    @State private var problem: String?

    var body: some View {
        Section {
            Picker("", selection: $creating) {
                Text(L.t("accountCreate")).tag(true)
                Text(L.t("accountSignIn")).tag(false)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            TextField(L.t("accountUsername"), text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            // The hints are what make iOS offer a strong password when the
            // account is made and fill it in when it is used — which is what
            // rescues somebody, since there is no reset.
            SecureField(L.t("accountPassword"), text: $password)
                .textContentType(creating ? .newPassword : .password)
        } header: {
            Text(L.t("signInWhy")).textCase(nil)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let problem {
                    Text(problem).foregroundStyle(Theme.bad)
                }
                if creating {
                    Text(L.t("accountUsernameHint"))
                    Text(L.t("appNoReset"))
                }
            }
        }
        .listRowBackground(Theme.card)
        .onChange(of: creating) { problem = nil }

        Section {
            Button(action: go) {
                Text(working ? L.t("accountWorking") : (creating ? L.t("accountCreate") : L.t("accountSignIn")))
            }
            .buttonStyle(.big)
            .disabled(working || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func go() {
        working = true
        problem = nil
        Task {
            defer { working = false }
            do {
                try await store.enter(username: username, password: password, create: creating)
                if store.user != nil { password = "" } else { problem = L.t("accountErrGeneric") }
            } catch let refusal as API.Refusal {
                problem = Self.sentence(refusal.code)
            } catch {
                problem = L.t("signInProblem")
            }
        }
    }

    /// The site's word for a refusal, as the website's sheet says it.
    private static func sentence(_ code: String) -> String {
        switch code {
        case "taken": return L.t("accountErrTaken")
        case "username": return L.t("accountErrUsername")
        case "password": return L.t("accountErrPassword")
        case "no-match": return L.t("accountErrNoMatch")
        case "slow-down": return L.t("accountErrSlow")
        default: return L.t("accountErrGeneric")
        }
    }
}

struct SignInDoors: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    /// Called once somebody is in.
    var entered: () -> Void = {}

    @State private var working = false
    @State private var problem = false

    var body: some View {
        VStack(spacing: 10) {
            if store.appleOffered {
                Button { enter(apple: true) } label: {
                    door(L.t("appApple")) {
                        Image(systemName: "apple.logo").font(.system(size: 19, weight: .medium))
                    }
                    // Apple's own button: black by day, white by night.
                    .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    .background(scheme == .dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if store.googleOffered {
                Button { enter(apple: false) } label: {
                    door(L.t("accountGoogle")) {
                        Image("GoogleMark").resizable().frame(width: 18, height: 18)
                    }
                    // Google's: its mark on white, in both.
                    .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1))
                }
            }
            if problem {
                Text(L.t("signInProblem")).font(.footnote).foregroundStyle(Theme.bad)
            }
        }
        .buttonStyle(.plain)
        .disabled(working)
    }

    private func door<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 8) {
            mark()
            Text(title).font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private func enter(apple: Bool) {
        working = true
        problem = false
        Task {
            defer { working = false }
            do {
                if apple { try await store.enterWithApple() } else { try await store.enterWithGoogle() }
                if store.user != nil { entered() } else { problem = true }
            } catch is SocialSignIn.Cancelled {
                // Somebody closed the sheet. Nothing to say.
            } catch {
                problem = true
            }
        }
    }
}
