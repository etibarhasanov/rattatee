import SwiftUI

/// What the foot of the Record tab becomes once Finish is pressed.

/// "8.6 km · 34 min" under a card's title.
private func summary(_ ride: Ride) -> String {
    L.distance(ride.metres) + " · " + L.duration(ride.ridden())
}

/// "Today 08:12 – 08:49" under a card's title, and under a ride's own page:
/// when the ride began and ended.
func when(_ ride: Ride) -> String {
    guard let (from, to) = ride.span else { return L.date(ride.started) }
    let day = Calendar.current.isDateInToday(from) ? L.t("today") : L.date(from)
    return "\(day) \(L.time(from)) – \(L.time(to))"
}

/// What one ride came to: how far, how long, how fast on average, and the
/// fastest half-minute — a ride's own numbers and no totals, since the point
/// of the app is the ride and nothing round it. A number there is not enough
/// of the ride for is a dash.
///
/// Where Finish left a walk or a drive out (`Motion`), the time is shown
/// twice — active, which the average is taken over, and total, Start to
/// Finish without the pauses — and the distance is the distance ridden. A
/// ride with nothing left out looks as it always did.
struct RideNumbers: View {
    let ride: Ride

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
            if ride.trimmed {
                GridRow {
                    Figure(value: L.distance(ride.metres), label: L.t("statDistanceRidden"))
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                GridRow {
                    Figure(value: L.clock(ride.ridden()), label: L.t("statActiveTime"))
                    Figure(value: L.clock(ride.seconds()), label: L.t("statTotalTime"))
                }
                GridRow {
                    Figure(value: speed, label: L.t("statAverageActive"))
                    Figure(value: top, label: L.t("statTop"))
                }
            } else {
                GridRow {
                    Figure(value: L.distance(ride.metres), label: L.t("statDistance"))
                    Figure(value: L.clock(ride.seconds()), label: L.t("statRidingTime"))
                }
                GridRow {
                    Figure(value: speed, label: L.t("statAverage"))
                    Figure(value: top, label: L.t("statTop"))
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var speed: String { ride.average.map { String(format: "%.1f km/h", $0) } ?? "–" }
    private var top: String { ride.topSpeed.map { String(format: "%.0f km/h", $0) } ?? "–" }

}

/// One of a ride's numbers, large, with what it is under it in capitals: the
/// save card's and the ride page's.
struct Figure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label.uppercased()).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Save this ride?

struct SaveCard: View {
    @Environment(Store.self) private var store
    let ride: Ride

    @State private var name = ""
    @State private var throwing = false
    @FocusState private var typing: Bool

    var body: some View {
        SheetCard {
            Text(L.t("rideNice")).font(.title2.bold()).foregroundStyle(Theme.ink)
            Text(when(ride)).font(.subheadline).foregroundStyle(Theme.muted)
            RideNumbers(ride: ride)
            // Fifty metres is a fix wandering, not a walk worth a sentence.
            if ride.leftOut >= 50 {
                Note(text: L.t("rideLeftOut", ["dist": L.distance(ride.leftOut)])).padding(.bottom, 12)
            }

            HStack {
                TextField(L.t("rideName"), text: $name)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit { typing = false }
                    .onChange(of: name) { _, now in
                        // The server's MAX_NAME, stopped at the keystroke.
                        if now.count > Store.longestName { name = String(now.prefix(Store.longestName)) }
                    }
                Text("\(name.count)/\(Store.longestName)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))

            // The two things somebody wants to know before pressing Save.
            Note(text: L.t("rideSaveWhyApp")).padding(.top, 8).padding(.bottom, 12)

            Button(L.t("rideSave")) {
                typing = false
                Task { await store.save(name: name) }
            }
            .buttonStyle(.big)

            ThrowButton(throwing: $throwing)
        }
    }
}

/// Throw it away, asked twice: a mis-tap here is twenty kilometres gone, and
/// nothing else in the app cannot be undone.
private struct ThrowButton: View {
    @Environment(Store.self) private var store
    @Binding var throwing: Bool

    var body: some View {
        Button(L.t("rideThrow")) { throwing = true }
            .font(.body.weight(.medium))
            .foregroundStyle(Theme.bad)
            .frame(maxWidth: .infinity, minHeight: 48)
            .confirmationDialog(L.t("rideThrow"), isPresented: $throwing, titleVisibility: .hidden) {
                Button(L.t("rideThrow"), role: .destructive) { store.throwAway() }
            }
    }
}

// MARK: Too short to keep

struct ShortCard: View {
    @Environment(Store.self) private var store
    let ride: Ride
    @State private var throwing = false

    var body: some View {
        SheetCard {
            Text(L.t("rideShortTitle")).font(.title2.bold()).foregroundStyle(Theme.ink)
            Text(summary(ride)).font(.subheadline).foregroundStyle(Theme.muted)
            Note(text: L.t("rideShortWhy", ["dist": L.distance(Store.shortest)]))
                .padding(.top, 10).padding(.bottom, 14)
            Button(L.t("rideKeepGoing")) { store.resume() }
                .buttonStyle(.big)
            ThrowButton(throwing: $throwing)
        }
    }
}

// MARK: After Save

/// What became of the ride Save was pressed on. It is one of four things,
/// and three of them are not a failure: saved; still being sent; kept on the
/// phone to be sent later; or refused for good by the server.
struct OutcomeCard: View {
    @Environment(Store.self) private var store
    let ride: Ride

    var body: some View {
        SheetCard {
            switch ride.status {
            case .saved:
                Text(L.t("rideSaved")).font(.title2.bold()).foregroundStyle(Theme.ink)
                Text(ride.name.isEmpty ? when(ride) : ride.name + " · " + when(ride))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                RideNumbers(ride: ride)
                Note(text: L.t("rideSavedWhyApp")).padding(.bottom, 14)
                done
            case .refused:
                head(L.t("badgeNotKept", ["why": why(ride.problem)]))
                Note(text: ride.problem == "fast" ? L.t("rideFast") : ride.problem == "outside" ? L.t("rideOutside") : L.t("rideShortServer"))
                    .padding(.top, 10).padding(.bottom, 14)
                done
            default:
                if store.sendingId == ride.id {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L.t("rideSaving")).font(.title2.bold()).foregroundStyle(Theme.ink)
                    }
                    Text(summary(ride)).font(.subheadline).foregroundStyle(Theme.muted)
                        .padding(.bottom, 14)
                } else {
                    head(L.t("keptTitle"))
                    Note(text: ride.problem == "often" ? L.t("rideOften") : L.t("keptWhy"))
                        .padding(.top, 10).padding(.bottom, 14)
                    done
                }
            }
        }
    }

    @ViewBuilder
    private func head(_ title: String) -> some View {
        Text(title).font(.title2.bold()).foregroundStyle(Theme.ink)
        Text(ride.title + " · " + summary(ride)).font(.subheadline).foregroundStyle(Theme.muted)
    }

    private var done: some View {
        Button(L.t("done")) { store.shown = nil }.buttonStyle(.big)
    }
}

/// The reason a ride was not kept, in two words, for a badge and a title.
func why(_ problem: String?) -> String {
    switch problem {
    case "fast": return L.t("whyFast")
    case "short": return L.t("whyShort")
    case "outside": return L.t("whyOutside")
    default: return L.t("whyMalformed")
    }
}
