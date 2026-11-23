import SwiftUI

/// My rides: every ride recorded on this phone, newest first, each with
/// whether it reached the server. A row opens the ride (`RideView`).
///
/// At the top, what the rides add up to (`StatsCard`): the phone's for
/// Today, Week and Month, and for All, signed in, what the account's add up
/// to on the website once it has said — two sums that are not meant to
/// agree, the account's footed with what it counts. The card is a section
/// of the list, so a phone with no ride on it shows only that it has none,
/// signed in or not, and the account's sum waits for the first ride here.
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

    /// The account's totals, from the website, for All on the card: each
    /// time My rides appears and whenever who is signed in changes, which
    /// `AccountTotals` turns into once a minute at most. Nothing is asked
    /// signed out, nor for CI's screenshots. It is asked whichever span is
    /// chosen, so All has its numbers by the time it is pressed.
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
            Section { StatsCard(rides: listed, user: store.demo ? nil : store.user) }
                .listRowBackground(Theme.card)
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
