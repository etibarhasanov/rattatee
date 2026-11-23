import Foundation
import Observation

/// The app's words, in English, Estonian, Russian and Azerbaijani.
///
/// Kohuke reads most of its strings from the website at launch. Rattatee
/// cannot: it has to say "Recording" in a pocket on a train with no signal,
/// and the website has nothing to say about riding. So every string is
/// compiled in, from `Seed/strings.json`. The ones the website has too were
/// copied from its `data/ui.json` under the same keys — `account*` — so a
/// sentence fixed there can be copied here by key. The `ride*` ones are this
/// app's own.
///
/// The language is the one chosen under Account, or, until somebody
/// chooses, the one iOS picked for this app: the phone's own, or the one
/// chosen for Rattatee alone under Settings, which iOS offers because
/// Config/Info.plist lists all four. Anything else reads English.
///
/// The choice is read through `LangStore`, which is observable, so every
/// view that asks `L.t` for a sentence is redrawn the moment it changes —
/// no restart, the way the colour changes.
enum L {
    static let languages = ["en", "et", "ru", "az"]

    /// What iOS picked, used while the choice is "Phone's language".
    static let phone: String = {
        let first = Bundle.main.preferredLocalizations.first ?? "en"
        return languages.contains(first) ? first : "en"
    }()

    static var lang: String {
        let chosen = LangStore.shared.choice
        return languages.contains(chosen) ? chosen : phone
    }

    private static let table: [String: [String: String]] = {
        guard let data = Disk.seed("strings"),
              let table = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return table
    }()

    /// The sentence for a key, with `{name}`-style gaps filled.
    static func t(_ key: String, _ gaps: [String: String] = [:]) -> String {
        var text = table[key]?[lang] ?? table[key]?["en"] ?? key
        for (name, value) in gaps { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }

    /// A distance the way the website says one: metres under a kilometre,
    /// then kilometres to one decimal.
    static func distance(_ metres: Double) -> String {
        if metres < 1000 { return "\(Int((metres / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", metres / 1000)
    }

    /// Ride time as 17:08 or 1:12:40.
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Ride time for a list: "34 min" or "1:12".
    static func duration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        return minutes < 60 ? "\(minutes) min" : String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: lang)))
    }

    /// "14 Nov 2026": a day that may be in another year, with no weekday,
    /// which says nothing that far back.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: lang)))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(Locale(identifier: lang)))
    }
}

/// The language chosen under Account: one of `L.languages`, or empty for
/// the phone's own. Kept on the phone, beside the colour.
@Observable
final class LangStore {
    static let shared = LangStore()

    var choice: String {
        didSet { UserDefaults.standard.set(choice, forKey: "lang") }
    }

    private init() {
        choice = UserDefaults.standard.string(forKey: "lang") ?? ""
    }
}
