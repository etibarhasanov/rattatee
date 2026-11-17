import SwiftUI
import UIKit

/// The website's colours: its blue style by day and its green style by
/// night, following the phone's own light and dark. The values are the tokens
/// of the `[data-style]` blocks in `assets/styles.css` in the website repo,
/// copied from Kohuke's `Views/Theme.swift`. Kohuke lets you pick one of four
/// styles; Rattatee has no settings screen to put that on yet, and a
/// night ride wants the dark one without asking.
enum Theme {
    private static func pair(_ day: UInt32, _ night: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: night) : UIColor(hex: day) })
    }

    static let ink = pair(0x0F1D31, 0xE7F1EA)
    static let muted = pair(0x4D6079, 0xA2B7A9)
    static let paper = pair(0xEDF3FB, 0x101A15)
    static let wash = pair(0xD6E3F2, 0x25332C)
    static let hairline = pair(0xC6D6EA, 0x354740)
    static let accent = pair(0x1B4A8C, 0x6FD39A)
    /// The site's "you are here" colour, which is what a ride line is.
    static let here = pair(0xC0267E, 0xE0873A)
    static let card = pair(0xFFFFFF, 0x1D2A23)
    /// What is written on the accent: white by day, the ground by night.
    static let onAccent = pair(0xFFFFFF, 0x101A15)

    static let good = pair(0x1E7A46, 0x6FD39A)
    static let goodWash = pair(0xDDEFE2, 0x1F3A2A)
    static let wait = pair(0x8A5300, 0xF0B45A)
    static let waitWash = pair(0xFCEBD2, 0x3A2E18)
    static let bad = pair(0xB3261E, 0xF08A7E)
    static let badWash = pair(0xF6DADA, 0x3E2222)

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
