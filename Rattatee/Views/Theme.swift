import SwiftUI
import Observation
import UIKit

/// One of the website's four colours. The site gives each one a single
/// look — Red and Blue by day, Green and Plum by night — and here each has a
/// day and a night, so the colour and the background are two choices.
enum Hue: String, CaseIterable, Identifiable {
    case red, green, blue, plum

    var id: String { rawValue }

    /// Its name. Written out key by key so the strings check in CI can see
    /// every key the app asks for.
    var name: String {
        switch self {
        case .red: return L.t("lookRed")
        case .green: return L.t("lookGreen")
        case .blue: return L.t("lookBlue")
        case .plum: return L.t("lookPlum")
        }
    }
}

/// Light, dark, or as the phone is set, which is where a new install starts.
enum Look: String, CaseIterable, Identifiable {
    case phone, light, dark

    var id: String { rawValue }

    /// What SwiftUI is told to draw in: nothing, for the phone's own.
    var scheme: ColorScheme? {
        switch self {
        case .phone: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The values of one colour on one background.
///
/// By night, Green and Plum are the website's `[data-style]` tokens in
/// `assets/styles.css` to the value, as Kohuke's are, and Red and Blue were
/// drawn for this app to sit beside them: the same hue for the accent, its
/// ground tinted the way the site's own pair is. By day the ink, muted and
/// accent are still the colour's own — Red's and Blue's the site's — but the
/// ground is not: every colour stands on the same warm paper white (`dayPaper`
/// below), at the owner's word on 2026-11-23, where each had a pale tint of
/// its own hue that read as a template's.
///
/// `way` and `wayEdge` are this app's alone, since the site's map draws its
/// own: the suggested way on the map and the edge it is drawn inside. By day
/// the way is the accent itself, inside a darker shade of it; by night it is
/// a stronger shade of the same hue than the accent, inside the ground's own
/// dark — THE WAY IS SOLID, AND EDGED, in RideMap.swift.
struct Palette {
    let ink, muted, paper, wash, hairline, accent, here, card, onAccent, way, wayEdge: UInt32

    /// The ground by day, whatever the colour: a warm paper white, nearly
    /// neutral, so the accent is the only colour on the screen and the white
    /// cards sit just above it. `dayWash` is a step darker, for quiet buttons
    /// and chips; `dayHairline` another, for dividers and the edges of fields.
    static let dayPaper: UInt32 = 0xF6F4EF
    static let dayWash: UInt32 = 0xECE9E2
    static let dayHairline: UInt32 = 0xE2DED5

    static func of(_ hue: Hue, dark: Bool) -> Palette {
        switch (hue, dark) {
        case (.red, false):
            return Palette(ink: 0x27141A, muted: 0x7D5754, paper: dayPaper, wash: dayWash, hairline: dayHairline,
                           accent: 0xA81E28, here: 0x0B62C4, card: 0xFFFFFF, onAccent: 0xFFFFFF,
                           way: 0xA81E28, wayEdge: 0x5C1016)
        case (.red, true):
            return Palette(ink: 0xF6E8E6, muted: 0xC9A9A6, paper: 0x1C1012, wash: 0x3A2428, hairline: 0x4A3034,
                           accent: 0xF08A7E, here: 0x5AA2F0, card: 0x2A1A1D, onAccent: 0x1C1012,
                           way: 0xFF5A6E, wayEdge: 0x1C1012)
        case (.green, false):
            return Palette(ink: 0x13261B, muted: 0x4F6A58, paper: dayPaper, wash: dayWash, hairline: dayHairline,
                           accent: 0x1E7A46, here: 0xC05A12, card: 0xFFFFFF, onAccent: 0xFFFFFF,
                           way: 0x1E7A46, wayEdge: 0x104326)
        case (.green, true):
            return Palette(ink: 0xE7F1EA, muted: 0xA2B7A9, paper: 0x101A15, wash: 0x25332C, hairline: 0x354740,
                           accent: 0x6FD39A, here: 0xE0873A, card: 0x1D2A23, onAccent: 0x101A15,
                           way: 0x3DDC84, wayEdge: 0x101A15)
        case (.blue, false):
            return Palette(ink: 0x0F1D31, muted: 0x4D6079, paper: dayPaper, wash: dayWash, hairline: dayHairline,
                           accent: 0x1B4A8C, here: 0xC0267E, card: 0xFFFFFF, onAccent: 0xFFFFFF,
                           way: 0x1B4A8C, wayEdge: 0x0F294D)
        case (.blue, true):
            return Palette(ink: 0xE6EEF8, muted: 0xA3B3C7, paper: 0x0E1620, wash: 0x223044, hairline: 0x30415A,
                           accent: 0x8DB4F0, here: 0xE05AA8, card: 0x18222F, onAccent: 0x0E1620,
                           way: 0x4C9AFF, wayEdge: 0x0E1620)
        case (.plum, false):
            return Palette(ink: 0x22152C, muted: 0x6E5A7D, paper: dayPaper, wash: dayWash, hairline: dayHairline,
                           accent: 0x6B3FA0, here: 0xC05A12, card: 0xFFFFFF, onAccent: 0xFFFFFF,
                           way: 0x6B3FA0, wayEdge: 0x3B2358)
        case (.plum, true):
            return Palette(ink: 0xF1E9F6, muted: 0xB9A8C6, paper: 0x16111C, wash: 0x2E2638, hairline: 0x43384F,
                           accent: 0xC9A6F2, here: 0xE0873A, card: 0x271F30, onAccent: 0x16111C,
                           way: 0xB385FF, wayEdge: 0x16111C)
        }
    }
}

/// The colour and the background chosen under Account, kept on the phone as
/// the website keeps its style in the browser. Blue, as the phone is set,
/// until somebody chooses. Observable, and every colour below is read through
/// it, so the whole app is redrawn the moment either changes.
@Observable
final class StyleStore {
    static let shared = StyleStore()

    var hue: Hue {
        didSet { UserDefaults.standard.set(hue.rawValue, forKey: "hue") }
    }
    var look: Look {
        didSet { UserDefaults.standard.set(look.rawValue, forKey: "look") }
    }

    private init() {
        hue = UserDefaults.standard.string(forKey: "hue").flatMap(Hue.init(rawValue:)) ?? .blue
        look = UserDefaults.standard.string(forKey: "look").flatMap(Look.init(rawValue:)) ?? .phone
    }
}

/// The colours in use. Each is the chosen colour's day and night values, and
/// iOS picks between them by whether the screen is being drawn dark — which
/// is the phone's own setting, or Light or Dark where the root view forces
/// one (`preferredColorScheme` in RattateeApp.swift).
enum Theme {
    private static func token(_ pick: @escaping (Palette) -> UInt32) -> Color {
        let hue = StyleStore.shared.hue
        return Color(UIColor { traits in
            UIColor(hex: pick(Palette.of(hue, dark: traits.userInterfaceStyle == .dark)))
        })
    }

    private static func pair(_ day: UInt32, _ night: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: night) : UIColor(hex: day) })
    }

    static var ink: Color { token(\.ink) }
    static var muted: Color { token(\.muted) }
    static var paper: Color { token(\.paper) }
    static var wash: Color { token(\.wash) }
    static var hairline: Color { token(\.hairline) }
    static var accent: Color { token(\.accent) }
    /// The site's "you are here" colour, which is what a ride line is.
    static var here: Color { token(\.here) }
    /// The suggested way on the map, and the edge it is drawn inside.
    static var way: Color { token(\.way) }
    static var wayEdge: Color { token(\.wayEdge) }
    static var card: Color { token(\.card) }
    /// What is written on the accent: white by day, the ground by night.
    static var onAccent: Color { token(\.onAccent) }

    // Saved, waiting and not kept read the same whatever the colour.
    static let good = pair(0x1E7A46, 0x6FD39A)
    static let goodWash = pair(0xDDEFE2, 0x1F3A2A)
    static let wait = pair(0x8A5300, 0xF0B45A)
    static let waitWash = pair(0xFCEBD2, 0x3A2E18)
    static let bad = pair(0xB3261E, 0xF08A7E)
    static let badWash = pair(0xF6DADA, 0x3E2222)

    /// The train of a way by train, whatever the colour chosen: orange, as
    /// Elron's trains are, at the owner's word — its rail on the map, and
    /// the way's button on the card. A little lighter by night, for the
    /// faint rail of a way on offer to hold on a dark map.
    ///
    /// The day's is the orange Google's map draws Elron's line in, read off
    /// a screenshot the owner sent on 2026-11-20, so it is good to the few
    /// parts in 255 a compressed picture is. It was not read out of Elron's
    /// own files, which that session could not reach. Elron's exact orange,
    /// once somebody has it, goes here and nowhere else.
    static let train = pair(0xF06816, 0xFF8433)
    /// The darker edge the rail is drawn inside, off the same screenshot.
    static let trainEdge = pair(0x9C4818, 0x7A3610)
    /// What is written on that orange: near black by day and by night,
    /// since the orange is light in both and white on it is hard to read.
    static let onTrain = Color(UIColor(hex: 0x24130A))

    static let radius: CGFloat = 14
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// The big filled button: Start, Finish, Save ride.
struct BigButtonStyle: ButtonStyle {
    var filled = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(filled ? Theme.onAccent : Theme.ink)
            .background(filled ? Theme.accent : Theme.wash, in: RoundedRectangle(cornerRadius: Theme.radius))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

extension ButtonStyle where Self == BigButtonStyle {
    static var big: BigButtonStyle { BigButtonStyle() }
    static var bigQuiet: BigButtonStyle { BigButtonStyle(filled: false) }
}

/// The card at the foot of the Record tab, over the map.
struct SheetCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: -4)
                    .ignoresSafeArea(edges: .bottom)
            )
    }
}

/// A small line of explanation in the muted colour.
struct Note: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
