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
/// Russian is the exception: not the owner's voice but Dmitri's, an open
/// voice made on a computer, chosen by the owner for want of a Russian
/// speaker.
///
/// Where a recording is missing the phone's own voice reads the row's words
/// instead, in English and Russian.
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
    /// Whether it speaks: the voice's button at the end of the radio's row
    /// (`VoiceButton`). Kept on the phone, and on until somebody turns it
    /// off.
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
        case soon, left, right, straight, around, arrive, tunnel, off
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
        guard voice else { return }
        turns(here, on: way)
        board(here, on: way)
    }

    /// The train of a way by train, said on the way to its station: which
    /// train, where it is going and where to get off — "Train RE33 towards
    /// Narva at 06:25, get off at Ülemiste" — since the platform's board
    /// names where the train is going and not the rider's stop. No
    /// recording can say which train, so the phone's own voice reads it,
    /// where it has one for the language.
    ///
    /// Twice, as a corner is: from `soon`'s far end, whatever corners are
    /// still between, and again within `now` of the station. Until
    /// 2026-11-25 it was the second alone, and only once the station was
    /// the next corner — on the platform, after the choice of platform was
    /// made, and mostly not at all, since a point that near the rail is the
    /// train's and never reaches here. After the corner at this point and
    /// never over one being said, though a corner just after may cut it
    /// short, which is what the second time is for.
    private func board(_ here: CLLocationCoordinate2D, on way: Way) {
        guard !talking, let station = way.steps.first(where: { $0.turn == .train }) else { return }
        let spot = way.place(of: here)
        let left = station.along - spot.along
        guard spot.off <= Way.astray, left >= 0, left <= Self.soon.upperBound else { return }
        guard said.insert(left <= Self.now ? "train-now" : "train-soon").inserted else { return }
        speak(station.said)
    }

    /// The corner coming up, said about two hundred metres before it and
    /// at it.
    private func turns(_ here: CLLocationCoordinate2D, on way: Way) {
        // A roundabout is shown and not said, at the owner's word: a bike
        // is mostly on a path beside one, and "take the second exit" is a
        // sentence for a car. A station is `board`'s to say.
        guard let next = way.next(from: here) else { return }
        let corner = "\(Int(next.step.along))"
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

    /// The recordings one after another, or, where one of them is not in the
    /// bundle, the words in the phone's voice.
    private func say(_ clips: [Clip], _ words: String) {
        let files = clips.compactMap { Bundle.main.url(forResource: "\(L.lang)-\($0.rawValue)", withExtension: "m4a") }
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
        let code = ["en": "en-GB", "ru": "ru-RU"][L.lang] ?? ""
        guard let reader = AVSpeechSynthesisVoice(language: code) else { return }
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
