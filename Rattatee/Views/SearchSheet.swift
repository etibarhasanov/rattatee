import CoreLocation
import SwiftUI

/// Where to? — the search behind the bar on the Record tab.
///
/// Opened, before a letter is typed, it shows the places nearest the rider out
/// of the copy the phone keeps (`Venues`), with no wait and no signal needed.
/// Typed, the phone's copy answers at once, and the website's own search
/// replaces it when it answers: its places first, in the order it ranks
/// them, with their addresses, then streets and districts. From five letters
/// a last row offers to look on Google Maps, as the website's find bar does,
/// and what Google answers with goes to the top of the list. Choosing a row closes
/// the sheet and puts the place on the map with the way there.
struct SearchSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var found: [Spot] = []
    /// Which letters `found` is the answer to, so a slow answer to "pa" does
    /// not replace the answer to "paper".
    @State private var answered = ""
    @State private var failed = false
    @State private var searching = false

    @State private var googleReady = false
    @State private var asking = false
    /// What Google said for which letters: a sentence, when it found nothing.
    @State private var googleSaid: (q: String, text: String)?
    @FocusState private var typing: Bool

    private var q: String { text.trimmingCharacters(in: .whitespaces) }

    /// Whether the site has answered these letters. Until it has, the rows
    /// are the phone's.
    private var siteAnswered: Bool { answered == q && !failed }

    /// The rows on screen: the site's answer once it has one, and the
    /// phone's copy until then — or instead, when the site cannot be reached.
    private var rows: [Spot] {
        if q.count < Search.shortest { return [] }
        if siteAnswered { return found }
        return Venues.shared.matching(q, near: store.recorder.here)
    }

    /// Before anything is typed: the nearest places, or with no position
    /// yet, the places on the map.
    private var nearby: [Spot] {
        q.isEmpty ? Venues.shared.nearest(store.recorder.here) : []
    }

    var body: some View {
        NavigationStack {
            List {
                if !nearby.isEmpty {
                    Section {
                        ForEach(nearby) { spot in
                            Button { choose(spot) } label: { SpotRow(spot: spot, here: store.recorder.here) }
                                .listRowBackground(Theme.card)
                        }
                    } header: {
                        Text(store.recorder.here == nil ? L.t("searchKindMine") : L.t("searchNear"))
                    }
                }
                ForEach(rows) { spot in
                    Button { choose(spot) } label: { SpotRow(spot: spot, here: store.recorder.here) }
                        .listRowBackground(Theme.card)
                }
                // The phone's rows are up; the site's are on their way.
                if !rows.isEmpty && !siteAnswered && !failed {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if showsGoogle {
                    Section {
                        if asking {
                            HStack(spacing: 10) { ProgressView(); Text(L.t("findGoogleAsking")) }
                                .foregroundStyle(Theme.muted)
                        } else if let said = googleSaid, said.q == q {
                            Text(said.text).foregroundStyle(Theme.muted)
                        } else {
                            Button(L.t("findGoogleAsk", ["q": q])) { askGoogle() }
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .overlay { if rows.isEmpty && nearby.isEmpty { empty } }
            .navigationTitle(L.t("searchPrompt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L.t("close")) { dismiss() } }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: L.t("searchPrompt"))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .task {
            store.recorder.locate()
            // The copy the phone keeps is asked for at launch; this is for a
            // phone that had no signal then.
            Task { await Venues.shared.refresh() }
            googleReady = await Search.googleReady()
        }
        // Wait for a pause in the typing before asking, as the website does:
        // the task is cancelled and begun again at every keystroke.
        .task(id: q) {
            guard q.count >= Search.shortest else { found = []; answered = ""; failed = false; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search(q)
        }
    }

    /// Offered from five letters, once the site's own answer is in, as on
    /// the website — under whatever was found, or under nothing.
    private var showsGoogle: Bool {
        googleReady && q.count >= Search.googleFrom && answered == q && !failed
    }

    @ViewBuilder
    private var empty: some View {
        if q.count < Search.shortest {
            // Nothing typed yet, and nothing on the phone to show: nothing
            // to say.
            EmptyView()
        } else if failed {
            ContentUnavailableView(L.t("searchOfflineTitle"), systemImage: "wifi.slash",
                                   description: Text(L.t("searchOfflineWhy")))
        } else if searching || answered != q {
            ProgressView()
        } else if !showsGoogle {
            ContentUnavailableView(L.t("searchNoneTitle"), systemImage: "magnifyingglass",
                                   description: Text(L.t("searchNoneWhy")))
        }
    }

    private func search(_ q: String) async {
        searching = true
        defer { searching = false }
        // Side by side, and each may fail on its own.
        let here = store.recorder.here
        async let places = try? Search.places(q, near: here)
        async let streets = try? Search.streets(q)
        let (a, b) = await (places, streets)
        guard !Task.isCancelled else { return }
        // One of the two answering is an answer; neither is no connection.
        failed = a == nil && b == nil
        found = (a ?? []) + (b ?? [])
        answered = q
    }

    private func askGoogle() {
        let asked = q
        asking = true
        Task {
            let looked = await Search.google(asked)
            asking = false
            guard asked == q else { return }
            switch looked {
            case .found(let spots):
                // On top, and not twice: a place Google names may be one the
                // site's own search had already found.
                let known = Set(found.map(\.id))
                let new = spots.filter { !known.contains($0.id) }
                found = new + found
                googleSaid = (asked, L.t("findGoogleNoMore", ["q": asked]))
            case .nothing:
                googleSaid = (asked, L.t("findGoogleNone", ["q": asked]))
            case .resting:
                googleSaid = (asked, L.t("findGoogleResting"))
            case .off:
                googleReady = false
            }
        }
    }

    private func choose(_ spot: Spot) {
        store.head(to: spot)
        dismiss()
    }
}

struct SpotRow: View {
    let spot: Spot
    let here: CLLocationCoordinate2D?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.uppercased()).font(.caption2).foregroundStyle(Theme.accent)
                Text(spot.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                if !spot.detail.isEmpty {
                    Text(spot.detail).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let here {
                Text(L.distance(Geo.metres(Point(lat: here.latitude, lng: here.longitude, t: 0, acc: 0),
                                           Point(lat: spot.lat, lng: spot.lng, t: 0, acc: 0))))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .contentShape(Rectangle())
    }

    private var kind: String {
        switch spot.kind {
        case .mine: return L.t("searchKindMine")
        case .place: return L.t("searchKindPlace")
        case .street: return L.t("searchKindStreet")
        case .google: return L.t("findFromGoogle")
        }
    }
}
