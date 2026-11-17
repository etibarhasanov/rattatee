import SwiftUI

/// Add to a list: the rider's lists on the website, one press each, and a
/// new one made on the spot. `Core/Lists.swift` says where they come from
/// and what happens with no signal.
///
/// A place the website does not have — one only Apple's map names, or a pin
/// — goes on a list as the rider's own place, so it needs a name, and the
/// sheet asks for one, filled in with what the map called it.
struct ListPicker: View {
    let spot: Spot

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var newTitle = ""
    @State private var loading = true
    /// No signal, and no lists kept from before either.
    @State private var offline = false
    @State private var working: String?
    @State private var outcomes: [String: ListBook.Outcome] = [:]
    @State private var problem: String?

    init(spot: Spot) {
        self.spot = spot
        _name = State(initialValue: spot.kind == .pin && !spot.detail.isEmpty ? spot.detail : spot.name)
    }

    private var book: ListBook { ListBook.shared }
    private var named: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                if !spot.onRoll {
                    Section {
                        TextField(L.t("listPlaceName"), text: $name)
                    } footer: {
                        Text(L.t("listOwnPlace"))
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    if book.lists.isEmpty {
                        if loading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text(offline ? L.t("listOffline") : L.t("listsNone")).foregroundStyle(Theme.muted)
                        }
                    }
                    ForEach(book.lists) { list in
                        Button { add(to: list) } label: {
                            HStack {
                                Text(list.title).foregroundStyle(Theme.ink)
                                Spacer()
                                status(list)
                            }
                        }
                        .disabled(working != nil || outcomes[list.id] == .added || outcomes[list.id] == .waiting)
                    }
                } header: {
                    Text(L.t("listAddTo", ["name": named.isEmpty ? spot.name : named])).textCase(nil)
                }
                .listRowBackground(Theme.card)

                Section {
                    TextField(L.t("listsNewName"), text: $newTitle)
                    Button(L.t("listsCreate")) { make() }
                        .disabled(working != nil || newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    if let problem { Text(problem).foregroundStyle(Theme.bad) }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(L.t("goalList"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L.t("close")) { dismiss() } }
            }
        }
        .task {
            do { try await book.load() } catch { offline = book.lists.isEmpty }
            loading = false
        }
    }

    @ViewBuilder
    private func status(_ list: ListBook.Row) -> some View {
        if working == list.id {
            ProgressView()
        } else {
            switch outcomes[list.id] {
            case .added: Label(L.t("listsSaveDone"), systemImage: "checkmark").foregroundStyle(Theme.good)
            case .waiting: Text(L.t("listWaiting")).foregroundStyle(Theme.wait)
            default:
                Text(list.n == 1 ? L.t("listCountOne") : L.t("listCount", ["n": String(list.n)]))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func add(to list: ListBook.Row) {
        guard !named.isEmpty else { problem = L.t("listNameFirst"); return }
        working = list.id
        problem = nil
        Task {
            let outcome = await book.add(spot, name: named, to: list)
            working = nil
            outcomes[list.id] = outcome
            if case .refused(let code) = outcome { problem = Self.sentence(code) }
        }
    }

    private func make() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        working = "new"
        problem = nil
        Task {
            do {
                let list = try await book.create(title: title)
                newTitle = ""
                working = nil
                add(to: list)
            } catch let refusal as API.Refusal {
                working = nil
                problem = Self.sentence(refusal.code)
            } catch {
                working = nil
                problem = L.t("listOffline")
            }
        }
    }

    /// The website's word for a refusal, in the website's own sentences.
    private static func sentence(_ code: String) -> String {
        switch code {
        case "signed-out": return L.t("listsErrSignedOut")
        case "full": return L.t("listsErrFull")
        case "too-many": return L.t("listsErrTooMany")
        case "title": return L.t("listsErrTitle")
        default: return L.t("listsErrGeneric")
        }
    }
}
