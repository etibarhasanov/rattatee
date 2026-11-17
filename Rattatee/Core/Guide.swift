import AVFoundation
import CoreLocation
import Observation

/// The voice that says where the way turns.
///
/// A rider with somewhere to go has the phone in a pocket, which is the
/// whole point of the app, so the row on the riding screen that says "150 m,
/// turn right" is one nobody is looking at. This says it instead: once about
/// two hundred metres before a corner — "In 200 metres", then the turn — and
/// once at it.
///
/// WHOSE VOICE
///
/// The owner's, recorded: one short file a phrase, in each of the app's four
/// languages, under `Rattatee/Voice/` as `<lang>-<clip>.m4a` — `et-left.m4a`,
/// `ru-keep-right.m4a`. `docs/voice.md` is the list of them and what each
/// says. That is why the phrases are few and carry no street name and no
/// distance but the one: a recording can only say what was recorded. The
/// street is in the row.
///
/// Where a recording is missing — Azerbaijani and English are recorded so
/// far — the phone's own voice reads the row's words instead, in English and
/// Russian.
/// iOS has no Estonian or Azerbaijani voice, so in those a missing recording
/// is silence.
/// That is a stand-in for trying the thing out, not the plan.
///
/// IN A POCKET, OVER MUSIC
///
/// The audio session is `playback` with the `voicePrompt` mode: whatever
/// else is playing is turned down for the second the phrase takes and comes
/// back after, a podcast is paused rather than talked over, and the ringer
/// switch does not silence it, as it does not silence any navigation app.
/// Starting to play with the screen locked is what the `audio` background
/// mode in Config/Info.plist is for.
///
/// Nothing here knows about a ride. The Store hands it each point it keeps
/// while there is a way, so paused is silent, and so is a ride with nowhere
/// to go.
@MainActor
@Observable
final class Guide {
    /// Whether it speaks: the speaker button in the row. Kept on the phone,
    /// and on until somebody turns it off.
    var voice: Bool {
        didSet {
            UserDefaults.standard.set(voice, forKey: "voice")
            if !voice { hush() }
        }
    }

    /// How far before a corner it is announced: where the phrase "In 200
    /// metres" is near enough to true. A corner first seen closer than this
    /// is only said at the corner.
    static let soon: ClosedRange<Double> = 120...220
    /// And how near is "now".
    static let now: Double = 40

    /// One recording. The raw value is the file's name after the language.
    enum Clip: String, CaseIterable {
        case soon, left, right, straight, around, arrive
        case keepLeft = "keep-left"
        case keepRight = "keep-right"
    }

    /// What has been said on this way, so each corner is said twice and no
    /// more however many points arrive near it.
    @ObservationIgnored private var said = Set<String>()
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var ending: NSObjectProtocol?
    @ObservationIgnored private let talker = AVSpeechSynthesizer()

    init() {
        voice = UserDefaults.standard.object(forKey: "voice") as? Bool ?? true
        // The stand-in looks after its own audio: the system turns other
        // sound down for it and back up, with nothing to tidy here.
        talker.usesApplicationAudioSession = false
    }

    /// A new way, or none: nothing has been said on it.
    func forget() {
        said.removeAll()
        hush()
    }

    /// One point of the ride, on the way being ridden.
    func hear(_ here: CLLocationCoordinate2D, on way: Way) {
        // A roundabout is shown and not said, at the owner's word: a bike
        // is mostly on a path beside one, and "take the second exit" is a
        // sentence for a car.
        guard voice, let next = way.next(from: here), let turn = clip(next.step) else { return }
        let corner = "\(Int(next.step.along))"
        if next.metres <= Self.now {
            if said.insert(corner + "-now").inserted { say([turn], next.step.words) }
        } else if next.step.turn != .arrive, Self.soon.contains(next.metres) {
            if said.insert(corner + "-soon").inserted {
                say([.soon, turn], L.t("turnSoon") + ", " + next.step.words)
            }
        }
    }

    private func clip(_ step: Step) -> Clip? {
        switch step.turn {
        case .left: return .left
        case .right: return .right
        case .keepLeft: return .keepLeft
        case .keepRight: return .keepRight
        case .straight: return .straight
        case .around: return .around
        case .arrive: return .arrive
        case .roundabout: return nil
        }
    }

    /// The recordings one after another, or, where one of them is not in the
    /// bundle, the words in the phone's voice.
    private func say(_ clips: [Clip], _ words: String) {
        let files = clips.compactMap { Bundle.main.url(forResource: "\(L.lang)-\($0.rawValue)", withExtension: "m4a") }
        guard files.count == clips.count else { return speak(words) }
        hush()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let items = files.map { AVPlayerItem(url: $0) }
        let player = AVQueuePlayer(items: items)
        // When the last of them ends, the session is given back, which is
        // what turns the music up again.
        ending = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: items.last, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hush() }
        }
        self.player = player
        player.play()
    }

    private func speak(_ words: String) {
        let code = ["en": "en-GB", "ru": "ru-RU"][L.lang] ?? ""
        guard let reader = AVSpeechSynthesisVoice(language: code) else { return }
        let line = AVSpeechUtterance(string: words)
        line.voice = reader
        talker.stopSpeaking(at: .immediate)
        talker.speak(line)
    }

    /// Stop, and give the audio back to whatever had it.
    private func hush() {
        talker.stopSpeaking(at: .immediate)
        if let ending { NotificationCenter.default.removeObserver(ending) }
        ending = nil
        guard player != nil else { return }
        player?.pause()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
