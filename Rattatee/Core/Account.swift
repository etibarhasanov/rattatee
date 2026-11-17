import Foundation

/// Signing in and out, exactly as Kohuke does it — and optional here: a
/// ride is saved with or without an account (`Store`).
///
/// An account here is the website's account and nothing else: a session the
/// site hands back as its HttpOnly cookie, kept by `URLSession`'s shared
/// cookie store across launches. Google and Apple are the two ways in —
/// `SocialSignIn` says how — and their buttons are drawn only where the site
/// says it can answer them (`appGoogle` and `appApple` on `GET /api/account`).
///
/// Signing out keeps the rides on the phone: they are the phone's record.
/// A ride is filed under whoever is signed in at the moment it is sent, or
/// under nobody.
extension Store {
    /// Ask the site who this cookie belongs to, and which doors it offers.
    func whoAmI() async {
        guard !demo else { checked = true; return }
        if let data = try? await API.data("api/account"),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            user = object["user"] as? String
            googleOffered = object["appGoogle"] as? Bool ?? false
            appleOffered = object["appApple"] as? Bool ?? false
            #if DEBUG
            if LaunchScript.doors { googleOffered = true; appleOffered = true }
            #endif
        }
        // Offline, whoever was signed in last is still believed, so a rider
        // with no signal is not shown a sign-in screen.
        checked = true
        await sendWaiting()
    }

    /// Sign in through Google, making the account if this Google account has
    /// never been here. Throws `SocialSignIn.Cancelled` for a closed sheet.
    func enterWithGoogle() async throws {
        let trip = try await SocialSignIn.shared.google()
        let answer = try await API.postObject("api/account", [
            "action": "ticket",
            "ticket": trip.ticket,
            "verifier": trip.verifier
        ])
        await arrive(answer)
    }

    /// The same through Apple.
    func enterWithApple() async throws {
        let proof = try await SocialSignIn.shared.apple()
        let answer = try await API.postObject("api/apple", ["token": proof.token, "nonce": proof.nonce])
        await arrive(answer)
    }

    private func arrive(_ answer: [String: Any]) async {
        user = answer["user"] as? String
        await sendWaiting()
    }

    func signOut() async {
        _ = try? await API.post("api/account", ["action": "logout"])
        leave()
    }

    /// Delete the account for good, which App Review asks of every app that
    /// makes accounts. The site asks for the password again, or, for an
    /// account that never had one, the username typed out.
    func deleteAccount(confirmation: String) async throws {
        try await API.post("api/account", ["action": "delete", "current": confirmation, "username": confirmation])
        leave()
    }

    private func leave() {
        user = nil
        if let cookies = HTTPCookieStorage.shared.cookies(for: API.base) {
            for cookie in cookies where cookie.name == "ttb_s" { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
    }
}
