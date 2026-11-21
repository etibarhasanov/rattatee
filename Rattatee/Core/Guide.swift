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
/// A SHARP CORNER IS SAID FIFTY METRES BEFORE IT
///
/// At the corner is too late for a left or a right sharper than a street
/// corner, which a bike has to slow right down for, and two hundred metres
/// is too far to keep it in mind. The owner's word, on 2026-11-21: such a
/// turn is said fifty metres before it, "In 50 metres, turn left", and that
/// stands for the call at the corner, which would come a second or two
/// later and cut it off. Sharp is `sharp` degrees or more on the way's own
/// line (`Way.sharpness`). Where "In 50 metres" has no recording in the
/// language and the phone has no voice for it either, the corner is said at
/// the corner as before, rather than not at all.
///
/// WHOSE VOICE
///
/// The owner's, recorded: one short file a phrase, in each of the app's four
/// languages, under `Rattatee/Voice/` as `<lang>-<clip>.m4a` — `et-left.m4a`,
/// `ru-keep-right.m4a`. `docs/voice.md` is the list of them and what each
/// says. That is why the phrases are few and carry no street name and no
/// distance but the two: a recording can only say what was recorded. The
/// street is in the row.
///
/// Where a recording is missing — Russian is the one language not recorded
/// yet — the phone's own voice reads the row's words instead, in English and
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
/// OVER THE APP'S OWN RADIO
///
/// That turning down is something iOS does to other apps, not to this one.
/// While the app's radio is on (`Radio`) the session is the radio's and is
/// left alone: the phrase plays inside it, and the radio is asked to go
/// under it and come back — by `say` and `hush`, and for the phone's own
/// voice by `Finished`, which hears it end.
///
/// Nothing here knows about a ride. The Store hands it each point it keeps
/// while there is a way, so paused is silent, and so is a ride with nowhere
/// to go — but for the one line when a ride starts, "Good morning, let's
/// go", which the Store asks for (`greet`) with or without a way.
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
    /// Where a sharp corner is said instead, "In 50 metres". Thirty metres
    /// deep, so the points kept a dozen metres apart land in it at least
    /// twice; nearer than `now` is the corner's own call, which comes first.
    static let near: ClosedRange<Double> = 40...70
    /// How many degrees a left or a right turns, or more, to be sharp:
    /// clearly more than a street corner's ninety, so a square corner is
    /// said as it always was. One number, to change if it is said too often
    /// or not often enough.
    static let sharp: Double = 100

    /// One recording. The raw value is the file's name after the language.
    enum Clip: String, CaseIterable {
        case soon, near, left, right, straight, around, arrive, tunnel, off
        case morning, afternoon, evening, late
        case keepLeft = "keep-left"
        case keepRight = "keep-right"
        case wrongWay = "wrong-way"
    }

    /// What has been said on this way, so each corner is said twice and no
    /// more however many points arrive near it.
    @ObservationIgnored private var said = Set<String>()
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var ending: NSObjectProtocol?
    @ObservationIgnored private let talker = AVSpeechSynthesizer()
    @ObservationIgnored private let finished = Finished()
    /// The app's radio, which goes under a phrase and owns the session
    /// while it is on.
    @ObservationIgnored weak var radio: Radio?

    /// A phrase is being said: the radio does not give the session away
    /// under it.
    var talking: Bool { player != nil || talker.isSpeaking }

    init() {
        voice = UserDefaults.standard.object(forKey: "voice") as? Bool ?? true
        // The stand-in looks after its own audio: the system turns other
        // sound down for it and back up, with nothing to tidy here.
        talker.usesApplicationAudioSession = false
        talker.delegate = finished
        finished.done = { [weak self] in
            Task { @MainActor in
                // Cut off by the next phrase is not finished.
                guard let self, !self.talking else { return }
                self.radio?.duck(false)
            }
        }
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
        guard voice, let next = way.next(from: here) else { return }
        let corner = "\(Int(next.step.along))"
        // The station of a way by train: no recording says which train, so
        // the phone's own voice reads the row, once, on the platform.
        if next.step.turn == .train {
            if next.metres <= Self.now, said.insert(corner + "-now").inserted { speak(next.step.words) }
            return
        }
        guard let turn = clip(next.step) else { return }
        if next.metres <= Self.now {
            guard said.insert(corner + "-now").inserted else { return }
            // A tunnel just past the corner is said with it — "Turn left,
            // enter the tunnel" — since said on its own it would cut the
            // turn off a few metres later, which is the Veerenni path under
            // the railway exactly.
            if let after = way.steps.first(where: { $0.along > next.step.along }), after.turn == .tunnel,
               after.along - next.step.along <= Self.now,
               said.insert("\(Int(after.along))-now").inserted {
                return say([turn, .tunnel], next.step.words + ", " + after.words)
            }
            say([turn], next.step.words)
        } else if Self.near.contains(next.metres), turnsSharp(next.step, on: way), heard([.near, turn]) {
            // Said here, and not again at the corner: A SHARP CORNER IS SAID
            // FIFTY METRES BEFORE IT.
            guard said.insert(corner + "-near").inserted else { return }
            said.insert(corner + "-now")
            say([.near, turn], L.t("turnNear") + ", " + next.step.words)
        } else if next.step.turn != .arrive, Self.soon.contains(next.metres) {
            if said.insert(corner + "-soon").inserted {
                say([.soon, turn], L.t("turnSoon") + ", " + next.step.words)
            }
        }
    }

    /// The rider has left the way: said once when the Store first sees it,
    /// and not again until they have been back on a way. A new way is not
    /// announced — its first turn is, as any way's is.
    func warn(_ kind: Lost.Kind) {
        guard voice else { return }
        switch kind {
        case .off: say([.off], L.t("lostOff"))
        case .back: say([.wrongWay], L.t("lostBack"))
        }
    }

    /// A new ride has started: one line for the time of day, said once.
    /// Not on a resume — the Store calls this from `start()` only — and the
    /// first turn, if it comes while this is still playing, cuts it off.
    func greet(at now: Date = Date()) {
        guard voice else { return }
        let (clip, text) = Self.greeting(hour: Calendar.current.component(.hour, from: now))
        say([clip], text)
    }

    /// Which greeting an hour of the phone's clock gets: its recording, and
    /// its words for the phone's voice where there is none. Written out key
    /// by key so the strings check in CI can see every key the app asks for.
    static func greeting(hour: Int) -> (Clip, String) {
        switch hour {
        case 5..<12: return (.morning, L.t("greetMorning"))
        case 12..<18: return (.afternoon, L.t("greetAfternoon"))
        case 18..<22: return (.evening, L.t("greetEvening"))
        default: return (.late, L.t("greetLate"))
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
        case .tunnel: return .tunnel
        case .roundabout, .train: return nil
        }
    }

    /// Whether a corner is a sharp left or right, on the way's own line.
    private func turnsSharp(_ step: Step, on way: Way) -> Bool {
        (step.turn == .left || step.turn == .right) && way.sharpness(at: step.along) >= Self.sharp
    }

    /// Whether a sentence would be heard at all: every recording of it is in
    /// the bundle, or the phone has a voice of its own for the language.
    private func heard(_ clips: [Clip]) -> Bool {
        clips.allSatisfy { file($0) != nil } || reader != nil
    }

    /// The recording of a phrase in the app's language, if it was made.
    private func file(_ clip: Clip) -> URL? {
        Bundle.main.url(forResource: "\(L.lang)-\(clip.rawValue)", withExtension: "m4a")
    }

    /// The phone's own voice for the app's language: English and Russian.
    /// iOS has none for Estonian or Azerbaijani.
    private var reader: AVSpeechSynthesisVoice? {
        guard let code = ["en": "en-GB", "ru": "ru-RU"][L.lang] else { return nil }
        return AVSpeechSynthesisVoice(language: code)
    }

    /// The recordings one after another, or, where one of them is not in the
    /// bundle, the words in the phone's voice.
    private func say(_ clips: [Clip], _ words: String) {
        let files = clips.compactMap { file($0) }
        guard files.count == clips.count else { return speak(words) }
        hush()
        if let radio, radio.on {
            radio.duck(true)
        } else {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .voicePrompt,
                                     options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try? session.setActive(true)
        }
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
        guard let reader else { return }
        let line = AVSpeechUtterance(string: words)
        line.voice = reader
        talker.stopSpeaking(at: .immediate)
        // Beside the radio it speaks in the radio's session and the radio
        // goes under it; alone, the system looks after it as before.
        let beside = radio?.on == true
        talker.usesApplicationAudioSession = beside
        if beside { radio?.duck(true) }
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
        // Back up, whether or not it is still on: a radio switched off
        // under a phrase must not come back quiet. And where it is on, the
        // session is the radio's to give back.
        radio?.duck(false)
        if radio?.on == true { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Hears the phone's own voice finish a line, or be cut off, which a
/// synthesizer says only to a delegate, and a delegate has to be an object
/// of Objective-C's.
private final class Finished: NSObject, AVSpeechSynthesizerDelegate {
    var done: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        done?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        done?()
    }
}
