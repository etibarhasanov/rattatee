import SwiftUI

/// How far, how many and how long, at the top of My rides: today, this
/// week, this month, or every ride on the phone.
///
/// All of it is added up on the phone from the rides `RidesTab` already
/// lists, so it costs no request and works with no signal. Nothing is asked
/// of the website for it on purpose: the phone has every ride it recorded,
/// and the server does not know which of its rides are this rider's — one
/// saved with no account is nobody's from the next day on — so its totals
/// would be smaller than the phone's and need sending to say so. The
/// website's own sum, of a signed-in account's rides from any phone, is
/// the section under this card instead (`AccountTotalsSection`), and the
/// two are not meant to agree.
///
/// Waiting rides count with saved ones, since they were ridden; a ride the
/// server refused for good (too short, too fast) does not, the same way it
/// is listed as Not kept. A week starts on Monday and a month on its 1st, in
/// the phone's own time zone — the calendar the rider lives by, rather than
/// a rolling seven or thirty days that would change under them by the hour.
struct StatsCard: View {
    let rides: [Ride]

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
        let totals = Totals(rides: counted, span: span)
        VStack(alignment: .leading, spacing: 12) {
            Picker(L.t("statsSpan"), selection: $span) {
                ForEach(Span.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(L.distance(totals.metres))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()

            if totals.count == 0 {
                Text(span.none)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                Text([totals.count == 1 ? L.t("statsRidesOne") : L.t("statsRidesMany", ["n": String(totals.count)]),
                      L.t("statsRiding", ["time": L.duration(totals.seconds)])].joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            if span == .week { WeekBars(days: totals.days) }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var counted: [Ride] {
        rides.filter { $0.status == .waiting || $0.status == .saved }
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
