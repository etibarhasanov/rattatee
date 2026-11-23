import Foundation
import Observation

/// What the website has added up of the signed-in rider's rides, for All
/// on the card at the top of My rides (`StatsCard`).
///
/// Since 2026-11-22 every ride a signed-in rider saves carries its summary
/// (`Ride.summary`): how far, how long, how long stopped, its top speed and
/// fastest kilometre. The website keeps one row an account, which each save
/// adds to — the ride outside the four cities too, which it keeps no line
/// of — and `GET /api/rides?totals=1` answers that row. So these are every
/// ride saved to the account from any phone, which is not what the card's
/// Today, Week and Month add up, nor its All signed out or before the
/// website has answered: those are this phone's rides, signed in or not,
/// waiting ones included. The two differ, and are meant to.
///
/// HOW OFTEN IT ASKS
///
/// When My rides appears with somebody signed in, and when who is signed in
/// changes — and not again for the same account within `every`, a minute,
/// however often the tab is opened. Never in the background, never on a
/// timer, and never signed out. My rides is opened more often than Account,
/// and the minute is what holds it: a rider going back and forth between
/// tabs asks once, so a thousand riders who each look a few times a day
/// are a few thousand requests a day, each reading the one row. The
/// last-asked time is kept in memory only, so a relaunch may ask once
/// more, which is one request.
///
/// KEPT ON THE PHONE, FOR THE ACCOUNT IT WAS
///
/// The last answer is kept in `totals.json` beside the lists, with whose
/// it was and when it came, so All opens on the account's numbers rather
/// than on the phone's until an answer comes, and with no signal says how
/// old they are. Before there has ever been one, All is the phone's sum,
/// with no spinner. It is shown only to the account it was asked for, and
/// goes on sign-out and on deleting the account (`Store.leave`), as the
/// lists do.
@MainActor
@Observable
final class AccountTotals {
    static let shared = AccountTotals()

    /// `totals` as the website answers it. Every number but the count is
    /// read as a Double, so one sent with a fraction is not a failure.
    struct Sum: Codable, Equatable {
        /// How many rides have been added up.
        let rides: Int
        let meters: Double
        /// Riding time: the active time each ride was saved with.
        let seconds: Double
        let stopped: Double
        /// The fastest half-minute of any ride, in km/h; nil for none.
        let top: Double?
        /// The fastest whole kilometre of any ride, in seconds; nil for none.
        let fastest: Double?
        /// The longest ride, in metres.
        let longest: Double
        /// When the first ride was added up, in milliseconds since 1970.
        let since: Double

        var first: Date { Date(timeIntervalSince1970: since / 1000) }
    }

    /// An answer and what it was an answer to. `sum` nil is the website
    /// saying no ride has been added up yet.
    struct Answer: Codable, Equatable {
        let user: String
        let sum: Sum?
        let at: Date
    }

    private struct Reply: Decodable {
        let ready: Bool
        let user: String?
        let totals: Sum?
    }

    /// The last answer the website gave, for whichever account asked.
    private(set) var answer: Answer?
    /// The last question went unanswered: no signal, or the website could
    /// not say (`ready: false`, a refusal, an answer for nobody).
    private(set) var failed = false

    /// Not asked again for the same account sooner than this.
    static let every: TimeInterval = 60
    @ObservationIgnored private var askedAt: Date?
    @ObservationIgnored private var askedFor: String?

    private static var file: URL { Disk.support.appendingPathComponent("totals.json") }

    private init() {
        answer = (try? Data(contentsOf: Self.file)).flatMap { try? JSONDecoder().decode(Answer.self, from: $0) }
    }

    /// The answer kept for this account, and never another's.
    func kept(for user: String) -> Answer? {
        answer?.user == user ? answer : nil
    }

    /// Ask the website for this account's totals, unless it was asked
    /// within the last minute. Whatever was kept stays on the screen until
    /// the answer comes, and after it if none does.
    func ask(for user: String) {
        if askedFor == user, let askedAt, Date().timeIntervalSince(askedAt) < Self.every { return }
        if askedFor != user { failed = false }
        askedFor = user
        askedAt = Date()
        Task {
            let reply = (try? await API.data("api/rides", ["totals": "1"]))
                .flatMap { try? JSONDecoder().decode(Reply.self, from: $0) }
            // Signed out, or somebody else signed in, while it was out:
            // this answer is nobody's now.
            guard askedFor == user else { return }
            // An answer for nobody is a session the website no longer
            // honours; `whoAmI` will hear the same the next time it asks.
            guard let reply, reply.ready, reply.user == user else {
                failed = true
                return
            }
            failed = false
            let answer = Answer(user: user, sum: reply.totals, at: Date())
            self.answer = answer
            if let data = try? JSONEncoder().encode(answer) { try? data.write(to: Self.file, options: .atomic) }
        }
    }

    /// Signed out, or the account deleted: the numbers were somebody's.
    func forget() {
        answer = nil
        failed = false
        askedAt = nil
        askedFor = nil
        try? FileManager.default.removeItem(at: Self.file)
    }
}
