import Foundation

/// Signing in and out, exactly as Kohuke does it — and optional here: a
/// ride is saved with or without an account (`Store`).
///
/// An account here is the website's account and nothing else: a session the
/// site hands back as its HttpOnly cookie, kept by `URLSession`'s shared
/// cookie store across launches. There are three ways in, as in Kohuke: a
/// username and a password, made or used right here through the website's
/// own `create` and `login`; and Google and Apple — `SocialSignIn` says how —
/// whose buttons are drawn only where the site says it can answer them
/// (`appGoogle` and `appApple` on `GET /api/account`).
///
/// Signing out keeps the rides on the phone: they are the phone's record.
/// A ride is filed under whoever is signed in at the moment it is sent, or
/// under nobody. The lists, and any place still waiting to go on one, were
/// the account's, and go with it (`ListBook.forget`).
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

    /// Make an account with a username and a password, or sign in with one.
    /// The site's refusal words come back as `API.Refusal` — `taken`,
    /// `username`, `password`, `no-match`, `slow-down` — and the form says
    /// each in a sentence of its own. There is no captcha on these two, so an
    /// app can use them as the website's sheet does.
    func enter(username: String, password: String, create: Bool) async throws {
        let answer = try await API.postObject("api/account", [
            "action": create ? "create" : "login",
            "username": username.trimmingCharacters(in: .whitespaces),
            "password": password
        ])
        await arrive(answer)
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
        ListBook.shared.forget()
        if let cookies = HTTPCookieStorage.shared.cookies(for: API.base) {
            for cookie in cookies where cookie.name == "ttb_s" { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
    }
}
