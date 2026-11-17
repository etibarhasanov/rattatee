import SwiftUI

/// The two ways in, Apple and Google, each drawn only where the site says it
/// can answer it (`appApple` and `appGoogle` on `GET /api/account`). The same
/// accounts as the website and Kohuke. Nothing in the app needs one — a ride
/// saves without — so this is drawn only on the Account sheet, and there is
/// no username form: an account with a password has a browser to make it in.
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
