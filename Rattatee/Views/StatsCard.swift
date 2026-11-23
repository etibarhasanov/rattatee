import SwiftUI

/// How far, how many and how long, at the top of My rides: today, this
/// week, this month, or all of it.
///
/// Today, Week and Month are added up on the phone from the rides
/// `RidesTab` already lists, so they cost no request and work with no
/// signal. Nothing is asked of the website for them on purpose: the phone
/// has every ride it recorded, and the server does not know which of its
/// rides are this rider's — one saved with no account is nobody's from the
/// next day on — so its sums would be smaller than the phone's and need
/// sending to say so.
///
/// ALL IS THE ACCOUNT'S, SIGNED IN
///
/// All is the one span the website can say better, for somebody signed in:
/// it adds up every ride saved to the account, from any phone, the ones
/// outside the four cities included (`AccountTotals`). Once it has
/// answered — just now, or on an earlier visit and kept on the phone — All
/// is that answer: the account's distance large, its rides and riding time
/// under it, then the time stopped, the average, the top speed, the
/// fastest kilometre and the longest ride, and at the foot a line saying
/// they are the account's and since when. The owner's word, on 2026-11-22,
/// was that these are part of All. The same day they had been a section
/// of their own under this card, On your account, and for a few hours
/// before that under the Account tab's signed-in rows. Today, Week and
/// Month stay the phone's, and All has no week bars, as it never had.
///
/// Until there is an answer with a ride in it, All is the phone's rides, as
/// it always was: signed out, in CI's screenshots, signed in before the
/// first answer has come, and for an account the website has added nothing
/// up for yet. There is no spinner. The phone's figures are numbers worth
/// showing while the website's are on their way, and a card that went to a
/// wait and back each time All was chosen would say less than either. With
/// no signal the last answer stays, and the foot says how old it is.
///
/// The two sums are not meant to agree, and the foot line is what says
/// which one All is showing. The account's has every ride from another
/// phone, and leaves out a ride still waiting here and one saved here with
/// nobody signed in; the phone's is the other way about.
///
/// In the phone's sums waiting rides count with saved ones, since they were
/// ridden; a ride the server refused for good (too short, too fast) does
/// not, the same way it is listed as Not kept. A week starts on Monday and a
/// month on its 1st, in the phone's own time zone — the calendar the rider
/// lives by, rather than a rolling seven or thirty days that would change
/// under them by the hour.
///
/// Every figure of the account's carries its unit: "9 h 43 min", "2 min
/// 17 s", "13.1 km/h". They said 9:43 and 2:17 at first, the way a ride's
/// row says a time, and the owner's word was that a figure by itself makes
/// no sense without one: a row's 34 min sits beside a distance and a date,
/// and a total stands alone. So the account's figures have their own two
/// ways of saying a time (`hours`, `minSec`), and `L.duration` and
/// `L.clock` stay as every other screen has them — the phone's own line on
/// this card included, which says "1:12 riding" past an hour as it always
/// has.
struct StatsCard: View {
    let rides: [Ride]
    /// Who is signed in, whose account All shows; nil signed out, and in
    /// CI's screenshots (`Store.demo`), which keeps All the phone's and asks
    /// the website nothing.
    let user: String?

    enum Span: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return L.t("statsToday")
            case .week: return L.t("statsWeek")
            case .month: return L.t("statsMonth")
            case .all: return L.t("statsAll")
            }
        }
        /// What a span with no riding in it says. `.all` never shows it:
        /// with no ride at all there is no card.
        var none: String {
            switch self {
            case .today: return L.t("statsNoneToday")
            case .week: return L.t("statsNoneWeek")
            case .month, .all: return L.t("statsNoneMonth")
            }
        }
    }

    @State private var span: Span = .week

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L.t("statsSpan"), selection: $span) {
                ForEach(Span.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if let account {
                accountFigures(account.sum, at: account.at)
            } else {
                phoneFigures(Totals(rides: counted, span: span))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var counted: [Ride] {
        rides.filter { $0.status == .waiting || $0.status == .saved }
    }

    /// The account's answer, kept or fresh, and when it came — for All,
    /// signed in, once the website has added up a ride for the account.
    /// Nil is the phone's own figures. Reading it here is what redraws the
    /// card when an answer comes in, `AccountTotals` being observed.
    private var account: (sum: AccountTotals.Sum, at: Date)? {
        guard span == .all, let user, let kept = AccountTotals.shared.kept(for: user),
              let sum = kept.sum else { return nil }
        return (sum, kept.at)
    }

    /// Today, Week and Month, and All with no answer from the website.
    @ViewBuilder
    private func phoneFigures(_ totals: Totals) -> some View {
        distance(totals.metres)
        if totals.count == 0 {
            Text(span.none)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        } else {
            count(totals.count, riding: L.duration(totals.seconds))
        }
        if span == .week { WeekBars(days: totals.days) }
    }

    /// All, signed in: what the website has added up of the account. A
    /// number it has none of — a top speed, a fastest kilometre — is a row
    /// left out rather than a dash, and so is the average with no riding
    /// time to take it over.
    @ViewBuilder
    private func accountFigures(_ sum: AccountTotals.Sum, at: Date) -> some View {
        distance(sum.meters)
        count(sum.rides, riding: Self.hours(sum.seconds))
        VStack(spacing: 6) {
            row(L.t("totalsStopped"), Self.hours(sum.stopped))
            if sum.seconds > 0 { row(L.t("totalsAverage"), Self.kmh(sum.meters / sum.seconds * 3.6)) }
            if let top = sum.top { row(L.t("totalsTop"), Self.kmh(top)) }
            if let fastest = sum.fastest { row(L.t("totalsFastest"), Self.minSec(fastest)) }
            row(L.t("totalsLongest"), L.distance(sum.longest))
        }
        Text(AccountTotals.shared.failed
             ? L.t("totalsAsOf", ["when": L.date(at) + " " + L.time(at)])
             : L.t("statsAllAccount", ["date": L.day(sum.first)]))
            .font(.footnote)
            .foregroundStyle(Theme.muted)
    }

    /// The big number.
    private func distance(_ metres: Double) -> some View {
        Text(L.distance(metres))
            .font(.system(size: 40, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .monospacedDigit()
    }

    /// "12 rides · 9 h 43 min riding", under the big number.
    private func count(_ n: Int, riding: String) -> some View {
        Text([n == 1 ? L.t("statsRidesOne") : L.t("statsRidesMany", ["n": String(n)]),
              L.t("statsRiding", ["time": riding])].joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
    }

    /// One of the account's figures: its name on the left, the figure on
    /// the right.
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(value).monospacedDigit().foregroundStyle(Theme.muted)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    /// A time in whole minutes, with its units: "9 h 43 min", or "43 min"
    /// under an hour. Under half a minute is "0 min", which is right for no
    /// standing at all; `L.duration` makes anything under a minute one,
    /// which is right for a ride's row.
    private static func hours(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return minutes < 60
            ? L.t("totalsMinutes", ["m": String(minutes)])
            : L.t("totalsHours", ["h": String(minutes / 60), "m": String(minutes % 60)])
    }

    /// The fastest kilometre: "2 min 17 s", where `L.clock` says 2:17.
    private static func minSec(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded()))
        return L.t("totalsMinSec", ["m": String(whole / 60), "s": String(whole % 60)])
    }

    private static func kmh(_ speed: Double) -> String {
        String(format: "%.1f km/h", speed)
    }
}

/// The sums for one span. `days` is the week's seven, Monday first, in
/// metres; empty for any other span.
struct Totals {
    var metres: Double = 0
    var seconds = 0
    var count = 0
    var days: [Double] = []

    /// Monday-first weeks in the phone's own time zone, whatever the
    /// phone's region says a week starts on.
    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    init(rides: [Ride], span: StatsCard.Span, now: Date = Date()) {
        let cal = Totals.calendar
        let from: Date?
        switch span {
        case .today: from = cal.startOfDay(for: now)
        case .week: from = cal.dateInterval(of: .weekOfYear, for: now)?.start
        case .month: from = cal.dateInterval(of: .month, for: now)?.start
        case .all: from = nil
        }
        if span == .week { days = Array(repeating: 0, count: 7) }
        for ride in rides {
            if let from, ride.started < from { continue }
            let m = ride.metres
            metres += m
            seconds += ride.ridden()
            count += 1
            if span == .week, let from {
                let day = cal.dateComponents([.day], from: from, to: cal.startOfDay(for: ride.started)).day ?? 0
                if (0..<7).contains(day) { days[day] += m }
            }
        }
    }
}

/// A bar a day, Monday to Sunday, the longest day full height and a day
/// with no riding a hairline.
private struct WeekBars: View {
    let days: [Double]

    var body: some View {
        let most = max(days.max() ?? 0, 1)
        let letters = Totals.calendar.veryShortWeekdaySymbolsMondayFirst
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(days.indices, id: \.self) { i in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(days[i] > 0 ? Theme.good : Theme.hairline)
                        .frame(height: days[i] > 0 ? max(4, 56 * days[i] / most) : 3)
                        .frame(height: 56, alignment: .bottom)
                    Text(letters[i])
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(letters[i]) \(L.distance(days[i]))")
            }
        }
    }
}

private extension Calendar {
    /// The one-letter day names in the chosen language, Monday first.
    var veryShortWeekdaySymbolsMondayFirst: [String] {
        var c = self
        c.locale = Locale(identifier: L.lang)
        let s = c.veryShortStandaloneWeekdaySymbols
        return Array(s[1...] + s[..<1])
    }
}
