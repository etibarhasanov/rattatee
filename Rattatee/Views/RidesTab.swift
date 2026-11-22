import SwiftUI

/// My rides: every ride recorded on this phone, newest first, each with
/// whether it reached the server. A row opens the ride (`RideView`).
///
/// At the top, what the phone's rides add up to (`StatsCard`), and under
/// it, signed in, what the account's add up to on the website
/// (`AccountTotalsSection`) — two sums that are not meant to agree, each
/// footed with what it counts. Both are sections of the list, so a phone
/// with no ride on it shows only that it has none, signed in or not, and
/// the account's sum waits for the first ride here.
///
/// The list is the phone's own. The server has a list of its own now
/// (`GET /api/rides?mine=1`, which the website's account page reads), but it
/// knows nothing of a ride still waiting here, which is the ride this
/// screen most needs to show. Reading the server's as well, so rides follow
/// an account to a new phone, is the next thing this tab would grow.
struct RidesTab: View {
    @Environment(Store.self) private var store
    /// The ride open over the list, by its id. CI's `-kOpen YES` starts on
    /// the newest, so the ride page can be photographed.
    @State private var path: [String] = {
        #if DEBUG
        if LaunchScript.open { return ["first"] }
        #endif
        return []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if listed.isEmpty {
                    ContentUnavailableView {
                        Label(L.t("ridesEmptyTitle"), systemImage: "bicycle")
                    } description: {
                        Text(L.t("ridesEmptyWhy"))
                    }
                    .foregroundStyle(Theme.muted)
                } else {
                    list
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(L.t("tabRides"))
            .navigationDestination(for: String.self) { id in
                RideView(id: id == "first" ? listed.first?.id ?? id : id)
            }
            .onAppear(perform: askTotals)
            .onChange(of: store.user) { askTotals() }
        }
    }

    /// The account's totals, from the website: each time My rides appears
    /// and whenever who is signed in changes, which `AccountTotals` turns
    /// into once a minute at most. Nothing is asked signed out, nor for
    /// CI's screenshots.
    private func askTotals() {
        guard !store.demo, let user = store.user else { return }
        AccountTotals.shared.ask(for: user)
    }

    /// Everything but the ride on the Record tab.
    private var listed: [Ride] {
        store.rides.filter { [.waiting, .saved, .refused].contains($0.status) }
    }

    /// The rides under the month they were ridden in, months newest first.
    private var months: [(title: String, rides: [Ride])] {
        var out: [(title: String, rides: [Ride])] = []
        for ride in listed {
            let title = ride.started
                .formatted(.dateTime.month(.wide).year().locale(Locale(identifier: L.lang)))
            if out.last?.title == title {
                out[out.count - 1].rides.append(ride)
            } else {
                out.append((title, [ride]))
            }
        }
        return out
    }

    private var list: some View {
        List {
            Section { StatsCard(rides: listed) }
                .listRowBackground(Theme.card)
            if !store.demo, let user = store.user {
                AccountTotalsSection(user: user)
            }
            if !store.waiting.isEmpty {
                Section { banner }
                    .listRowBackground(Theme.wash)
            }
            ForEach(months, id: \.title) { month in
                Section {
                    ForEach(month.rides) { ride in
                        NavigationLink(value: ride.id) { RideRow(ride: ride) }
                            .swipeActions {
                                // Only a ride the server has answered for
                                // good; a waiting one is never thrown away
                                // from here.
                                if ride.status != .waiting {
                                    Button(L.t("rideRemove"), role: .destructive) { store.remove(ride.id) }
                                }
                            }
                    }
                } header: {
                    Text(month.title)
                } footer: {
                    if month.title == months.last?.title {
                        Text(store.user == nil ? L.t("ridesFootPhone") : L.t("ridesFoot")).padding(.top, 6)
                    }
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// What is waiting, and the one thing that can be done about it.
    @ViewBuilder
    private var banner: some View {
        let n = store.waiting.count
        VStack(alignment: .leading, spacing: 8) {
            Text(n == 1 ? L.t("ridesWaitingOne") : L.t("ridesWaitingMany", ["n": String(n)]))
            if store.sendingId != nil {
                ProgressView()
            } else {
                Button(L.t("tryNow")) { Task { await store.sendWaiting(now: true) } }.fontWeight(.semibold)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.ink)
        .buttonStyle(.borderless)
    }
}

/// On your account: every ride saved to the account, from any phone, added
/// up by the website (`AccountTotals`). Directly under the phone's own sums,
/// signed in, and only there. It was added under the signed-in rows of the
/// Account tab and moved here the same day, 2026-11-22, at the owner's
/// asking.
///
/// It draws whatever is kept for this account at once, and the website's
/// answer when it comes. Before there has ever been one, a muted Distance
/// row waits with a spinner — or a dash, when the question went
/// unanswered. With no signal, what was kept stays, and the footer says
/// how old it is. An account with no ride added up yet says so in a line,
/// with no rows of noughts. A number the website has none of — a top speed,
/// a fastest kilometre — is a row left out rather than a dash.
///
/// Every figure carries its unit: "9 h 43 min", "2 min 17 s", "13.1 km/h".
/// It said 9:43 and 2:17 at first, the way a ride's row says a time, and
/// the owner's word was that a figure by itself makes no sense without one:
/// a row's 34 min sits beside a distance and a date, and a total stands
/// alone. So the totals have their own two ways of saying a time, and
/// `L.duration` and `L.clock` stay as every other screen has them.
private struct AccountTotalsSection: View {
    let user: String

    var body: some View {
        let book = AccountTotals.shared
        let kept = book.kept(for: user)
        Section {
            if let sum = kept?.sum {
                row(L.t("totalsDistance"), L.distance(sum.meters))
                row(L.t("totalsRides"), String(sum.rides))
                row(L.t("totalsRiding"), Self.hours(sum.seconds))
                row(L.t("totalsStopped"), Self.hours(sum.stopped))
                if sum.seconds > 0 { row(L.t("totalsAverage"), Self.kmh(sum.meters / sum.seconds * 3.6)) }
                if let top = sum.top { row(L.t("totalsTop"), Self.kmh(top)) }
                if let fastest = sum.fastest { row(L.t("totalsFastest"), Self.minSec(fastest)) }
                row(L.t("totalsLongest"), L.distance(sum.longest))
            } else if kept != nil {
                Text(L.t("totalsNone")).foregroundStyle(Theme.muted)
            } else {
                LabeledContent {
                    if book.failed { Text("–") } else { ProgressView() }
                } label: {
                    Text(L.t("totalsDistance"))
                }
                .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(L.t("totalsTitle"))
        } footer: {
            if let kept, book.failed {
                Text(L.t("totalsAsOf", ["when": L.date(kept.at) + " " + L.time(kept.at)]))
            } else if let sum = kept?.sum {
                Text(L.t("totalsWhy", ["date": L.day(sum.first)]))
            } else if kept == nil {
                Text(L.t("totalsWhyNoDate"))
            }
        }
        .listRowBackground(Theme.card)
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit().foregroundStyle(Theme.muted)
        } label: {
            Text(label).foregroundStyle(Theme.ink)
        }
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

struct RideRow: View {
    let ride: Ride

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ride.title)
                    .font(.body.weight(ride.name.isEmpty ? .medium : .semibold))
                    .foregroundStyle(ride.name.isEmpty ? Theme.muted : Theme.ink)
                    .lineLimit(1)
                Text([L.distance(ride.metres), L.duration(ride.ridden()),
                      L.date(ride.started) + " " + L.time(ride.started)].joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            StatusPill(ride: ride)
        }
        .padding(.vertical, 2)
    }
}

/// Saved, Waiting, or Not kept and why: a row's, and a ride page's.
struct StatusPill: View {
    let ride: Ride

    var body: some View {
        switch ride.status {
        case .saved:
            pill(L.t("badgeSaved"), Theme.good, Theme.goodWash)
        case .refused:
            pill(L.t("badgeNotKept", ["why": why(ride.problem)]), Theme.bad, Theme.badWash)
        default:
            pill(L.t("badgeWaiting"), Theme.wait, Theme.waitWash)
        }
    }

    private func pill(_ text: String, _ ink: Color, _ wash: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(wash, in: Capsule())
            .fixedSize()
    }
}
