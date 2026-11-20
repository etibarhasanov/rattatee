import Foundation

/// The one door to tallinntastebuds.ee.
///
/// Rattatee has no server of its own, the same as Kohuke and the map app. It
/// records a ride on the phone and hands it to `/api/rides`, the Function the
/// website's own recorder saves through, and asks `/api/account`,
/// `/api/google` and `/api/apple` who is riding.
///
/// Requests go through one `URLSession` whose cookie store is the system's.
/// The website's session is an HttpOnly cookie (`ttb_s`), and a native
/// session keeps and sends it by itself, so an account here is the website's
/// account. Copied from Kohuke's `Core/API.swift`, less what only flashcards
/// need.
enum API {
    static let base = URL(string: "https://tallinntastebuds.ee")!

    enum Failure: Error {
        case status(Int)
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Which version of the site's API this build asks. Every route Rattatee
    /// reads answers under `/api/v1/` as well as under its old `/api/`
    /// address, and a version in the address is a promise that it only ever
    /// gains fields: a change that would break a build in somebody's pocket
    /// is `/api/v2`, beside this one, and v1 keeps answering for at least six
    /// months. **The public API** in the website's `docs/handbook.md`; the
    /// map app's `API.versioned()` is the same function.
    static let version = "v1"

    /// The two routes whose v1 name is not their old one, because the
    /// website's public reads hold `places` and `lists` under `/api/v1/`:
    /// the city search is `find`, and your own lists are `me/lists`.
    private static let renamed = ["places": "find", "lists": "me/lists"]

    /// `api/<route>` as the code writes it, at this build's version:
    /// `api/rides` is `api/v1/rides`, `api/places` is `api/v1/find`. A path
    /// that already names its version — `api/v1/route`, which Where to? asks
    /// for the trains — and anything that is not a route are left as they are.
    static func versioned(_ path: String) -> String {
        guard path.hasPrefix("api/") else { return path }
        let route = String(path.dropFirst("api/".count))
        if route.range(of: #"^v[0-9]+/"#, options: .regularExpression) != nil { return path }
        return "api/\(version)/" + (renamed[route] ?? route)
    }

    /// A URL on the site, with an optional query.
    static func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var parts = URLComponents(url: base.appendingPathComponent(versioned(path)), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return parts.url!
    }

    /// The bytes of a path, or a thrown error for anything but a 2xx.
    static func data(_ path: String, _ query: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url(path, query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else { throw Failure.status(status) }
        return data
    }

    /// What a Function said when it refused: its `error` word ("short",
    /// "signed-out", "often") and the status it came with. A refusal is the
    /// server having answered; a thrown `URLError` is the server never
    /// having been reached, and the two are handled very differently by the
    /// upload queue — see `RideBook.send`.
    struct Refusal: Error {
        let code: String
        let status: Int
    }

    /// A JSON POST, the way the website's own pages send one. Answers the
    /// bytes that came back, or throws a `Refusal` carrying the route's own
    /// word for what went wrong.
    ///
    /// `signed: false` sends it with no cookie, so the website sees nobody
    /// signed in whoever is, and keeps none the answer sets. One caller: a
    /// ride saved with nobody signed in — `Store.send`.
    @discardableResult
    static func post(_ path: String, _ body: [String: Any], signed: Bool = true) async throws -> Data {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = signed
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw Refusal(code: object["error"] as? String ?? "status-\(http.statusCode)", status: http.statusCode)
        }
        return data
    }

    /// The same, read as a loose object, for the account routes whose answers
    /// are two or three fields.
    static func postObject(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let data = try await post(path, body)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static let privacy = base.appendingPathComponent("privacy")
}
