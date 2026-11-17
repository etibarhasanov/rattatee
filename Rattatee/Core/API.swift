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

    /// A URL on the site, with an optional query.
    static func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
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
    @discardableResult
    static func post(_ path: String, _ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
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
