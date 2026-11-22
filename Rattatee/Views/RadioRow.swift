import SwiftUI

/// The radio, at the foot of the riding screen over Pause and Finish.
///
/// One row, and what a car's radio has on its face: the station, a button
/// either side for the next and the one before, and the whole list behind a
/// longer press. Off, it is one line, "Play radio", and takes no more of the
/// card than that. A tap turns it on and off; where there was no signal, a
/// tap tries again.
///
/// Where there is somewhere to go, the voice's button is at its end
/// (`VoiceButton`, in RecordTab.swift), and the row is narrower by it: that
/// one is the voice, this one the music, and a rider can have either
/// without the other.
struct RadioRow: View {
    @Environment(Store.self) private var store
    @State private var choosing = LaunchScript.sheet == "stations"

    var body: some View {
        let radio = store.radio
        HStack(spacing: 6) {
            if radio.on { seek("chevron.left", L.t("radioPrev"), radio.state) { radio.step(-1) } }
            face(radio)
            if radio.on { seek("chevron.right", L.t("radioNext"), radio.state) { radio.step(1) } }
        }
        .padding(.horizontal, radio.on ? 8 : 14)
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(ink(radio.state))
        .background(ground(radio.state), in: RoundedRectangle(cornerRadius: Theme.radius))
        .sheet(isPresented: $choosing) { StationsSheet().environment(store) }
    }

    /// The middle of the row: what is playing, or what a tap would do.
    private func face(_ radio: Radio) -> some View {
        let says = words(radio)
        return HStack(spacing: 10) {
            Text(verbatim: "📻").font(.title2)
            VStack(alignment: .leading, spacing: 0) {
                Text(says.0).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                if let under = says.1 {
                    Text(under).font(.caption).lineLimit(1).minimumScaleFactor(0.8).opacity(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: radio.on ? .center : .leading)
        .contentShape(Rectangle())
        .onTapGesture { radio.press() }
        .onLongPressGesture(minimumDuration: 0.4) { choosing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(radio.state == .playing ? L.t("radioStop") + ", " + says.0 : says.0)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(L.t("radioHold"))) { choosing = true }
    }

    /// Next and previous, on a tint of whatever the row is written in.
    private func seek(_ symbol: String, _ label: String, _ state: Radio.State,
                      _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(ink(state).opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The line, and the smaller one under it where there is one.
    private func words(_ radio: Radio) -> (String, String?) {
        let name = radio.station?.name ?? L.t("radioTitle")
        switch radio.state {
        case .off: return (L.t("radioPlay"), nil)
        case .tuning: return (L.t("radioTuning"), name)
        case .playing: return (name, L.t("radioHold"))
        case .lost: return (L.t("radioLost"), L.t("radioRetry"))
        }
    }

    private func ink(_ state: Radio.State) -> Color {
        switch state {
        case .playing: return Theme.onAccent
        case .lost: return Theme.bad
        default: return Theme.ink
        }
    }

    private func ground(_ state: Radio.State) -> Color {
        switch state {
        case .playing: return Theme.accent
        case .lost: return Theme.badWash
        default: return Theme.wash
        }
    }
}

/// Every station, behind a longer press on the row: the one it is on between
/// two big buttons, and the list under it. A tap on a row plays it. The sheet
/// stays open, so one after another can be tried, and goes with a swipe.
struct StationsSheet: View {
    @Environment(Store.self) private var store

    var body: some View {
        let radio = store.radio
        VStack(alignment: .leading, spacing: 0) {
            Text(L.t("radioTitle").uppercased())
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                .padding(.bottom, 10)
            dial(radio)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(radio.stations.enumerated()), id: \.element.id) { index, station in
                        row(index + 1, station, on: station.id == radio.station?.id) { radio.choose(station) }
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private func dial(_ radio: Radio) -> some View {
        HStack(spacing: 10) {
            knob("chevron.left", L.t("radioPrev")) { radio.step(-1) }
            VStack(spacing: 2) {
                Text(radio.station?.name ?? "").font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(under(radio)).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            knob("chevron.right", L.t("radioNext")) { radio.step(1) }
        }
        .padding(12)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    /// "2 of 20 · English", or what it is doing where it is not yet playing.
    private func under(_ radio: Radio) -> String {
        switch radio.state {
        case .tuning: return L.t("radioTuning")
        case .lost: return L.t("radioLost")
        default:
            let count = L.t("radioOf", ["n": String(radio.place), "total": String(radio.stations.count)])
            return [count, radio.station?.note ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private func knob(_ symbol: String, _ label: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 52, height: 52)
                .background(Theme.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func row(_ number: Int, _ station: Station, on: Bool, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text(String(number)).font(.footnote.monospacedDigit()).foregroundStyle(Theme.muted)
                        .frame(width: 30, alignment: .leading)
                    Text(station.name).font(.body.weight(on ? .bold : .regular))
                        .foregroundStyle(on ? Theme.accent : Theme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(station.note ?? "").font(.footnote).foregroundStyle(on ? Theme.accent : Theme.muted)
                        .lineLimit(1)
                    if on {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.accent)
                            .padding(.leading, 6)
                    }
                }
                .frame(minHeight: 46)
                Divider().overlay(Theme.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
