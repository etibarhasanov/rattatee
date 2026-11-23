import AVFoundation
import MediaPlayer
import Observation

/// One station: a name, and the address its broadcaster sends its sound
/// from. `note` is the line beside it in the list, a language in its own
/// name or a word for the music; `lang` marks the station a language of the
/// app starts on.
struct Station: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    var note: String?
    var lang: String?
}

/// The radio on a ride: a station playing under the voice that says the
/// turns, the way a car's does under its navigation.
///
/// WHERE THE SOUND COMES FROM
///
/// Straight from the broadcaster. A station is the address a media player
/// would be given — an MP3 or AAC stream over HTTPS with no end — and the
/// phone opens it and plays what arrives. Nothing of it passes through
/// tallinntastebuds.ee, which costs the website nothing and the rider about
/// sixty megabytes of mobile data an hour. It is live: there is nothing to
/// rewind and no song to choose.
///
/// The stations are compiled in, `Seed/stations.json`: ERR's five and Radio
/// Paradise's two. App Review can ask to see each broadcaster's permission,
/// and these two are the only broadcasters likely to give it. The other
/// thirteen were taken off before release (README.md says why for each).
/// One comes back when its broadcaster says yes in writing, never just
/// because its address plays.
/// An address that dies is a line in that file and a new build; having the
/// website hand the list over instead is the next step, and README.md says
/// what it would promise.
///
/// WHICH STATION
///
/// The one the rider last chose, kept on the phone; one that has since left
/// the list counts as none chosen. Until they choose, the one marked for the
/// language the app is in — Raadio Tallinn in Estonian, Raadio 4 in Russian —
/// so the first press plays something they can follow. Azerbaijani has
/// none of its own, so it starts on the first, Raadio Tallinn.
///
/// WHEN IT PLAYS
///
/// When somebody presses it, and at the start of a ride if it was on when
/// the last one ended: the first time is always a press. It never starts
/// over something else — a rider with a podcast on keeps the podcast — and
/// it stops at Finish. Pause leaves it playing, as stopping at a light
/// leaves a car's.
///
/// UNDER THE VOICE
///
/// iOS turns other apps' sound down for a navigation prompt by itself
/// (`Guide`), but not an app's own. So while the radio is on the audio
/// session is the radio's — plain `playback`, kept active — and the Guide
/// plays inside it, asking this to `duck` for as long as a phrase takes.
///
/// WHEN THE SIGNAL GOES
///
/// A stream that fails or stalls is joined again, three times, a little
/// further apart each time; after that the button says No signal, and it is
/// tried again every half minute for as long as the radio is on, since the
/// phone is in a pocket and nobody is there to press anything. A phone call
/// pauses it and it rejoins after; pulling the headphones out stops it, as
/// every player on a phone does.
@MainActor
@Observable
final class Radio {
    enum State { case off, tuning, playing, lost }

    private(set) var state: State = .off
    let stations: [Station]
    /// The station chosen by hand, by id, or empty for the language's own.
    private var chosen: String {
        didSet { UserDefaults.standard.set(chosen, forKey: "station") }
    }

    var on: Bool { state != .off }

    /// The voice, so the session is not given away under a phrase.
    @ObservationIgnored weak var guide: Guide?
    /// Screenshots for CI: drawn, never played.
    @ObservationIgnored var demo = false

    /// How loud the radio is under the voice: there, and out of its way.
    static let under: Float = 0.12

    /// Whether the rider had it on: what a new ride starts from.
    private var wanted: Bool {
        get { UserDefaults.standard.bool(forKey: "radio") }
        set { UserDefaults.standard.set(newValue, forKey: "radio") }
    }
    /// A ride is under way, so the lock screen's play button may start it.
    @ObservationIgnored private var open = false
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var watching: [NSKeyValueObservation] = []
    @ObservationIgnored private var item: NSKeyValueObservation?
    @ObservationIgnored private var ducked = false
    @ObservationIgnored private var fade: Task<Void, Never>?
    /// Goes up with every join, so a timer from an older one knows it is old.
    @ObservationIgnored private var turn = 0
    @ObservationIgnored private var tries = 0
    /// A phone call has the sound: nothing is retried until it gives it back.
    @ObservationIgnored private var held = false

    init() {
        let data = Disk.seed("stations") ?? Data()
        stations = (try? JSONDecoder().decode([Station].self, from: data)) ?? []
        chosen = UserDefaults.standard.string(forKey: "station") ?? ""
        listen()
        remote()
    }

    /// The station it is on, or would be.
    var station: Station? {
        stations.first { $0.id == chosen }
            ?? stations.first { $0.lang == L.lang }
            ?? stations.first
    }

    /// Where that station is in the list, counted from one.
    var place: Int { (stations.firstIndex { $0.id == station?.id } ?? 0) + 1 }

    // MARK: What the rider does

    /// The button: on, off, or once more where there was no signal.
    func press() {
        if state == .off || state == .lost { play() } else { stop() }
    }

    func play() {
        wanted = true
        open = true
        tries = 0
        join()
    }

    /// Off, by hand: the next ride starts silent.
    func stop() {
        wanted = false
        quiet()
    }

    /// The next station, or the one before, round and round, as a car's
    /// seek buttons go.
    func step(_ by: Int) {
        guard !stations.isEmpty else { return }
        let next = (place - 1 + by + stations.count) % stations.count
        choose(stations[next])
    }

    /// A station picked from the list plays, whether the radio was on or not.
    func choose(_ station: Station) {
        chosen = station.id
        play()
    }

    // MARK: What a ride does

    /// A ride has started, or is riding again: on if it was on last time,
    /// and never over something the rider is already listening to.
    func begin() {
        open = true
        guard wanted, !on, !demo, !AVAudioSession.sharedInstance().isOtherAudioPlaying else { return }
        tries = 0
        join()
    }

    /// The ride is over. What the rider wanted is kept for the next one.
    func halt() {
        open = false
        quiet()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Down for a phrase and back up after it: a third of a second each way,
    /// so the voice is not stepped on and the music does not jump.
    func duck(_ down: Bool) {
        ducked = down
        fade?.cancel()
        guard let player else { return }
        let from = player.volume
        let to: Float = down ? Self.under : 1
        fade = Task { [weak self] in
            for step in 1...8 {
                try? await Task.sleep(for: .milliseconds(40))
                if Task.isCancelled { return }
                self?.player?.volume = from + (to - from) * Float(step) / 8
            }
        }
    }

    /// A state to photograph, with nothing playing.
    func pretend(_ state: State) {
        demo = true
        self.state = state
    }

    // MARK: The stream

    /// Join the station's stream where it now is. A live stream has no
    /// position, so every join is a new item: one that was paused or failed
    /// is thrown away rather than woken. `showing` is what the button says
    /// meanwhile — Tuning in, or still No signal on a try nobody asked for.
    private func join(showing: State = .tuning) {
        guard let station, !demo else { return }
        turn += 1
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)

        let player = self.player ?? build()
        let stream = AVPlayerItem(url: station.url)
        // An address that answers with nothing to play says so here.
        item = stream.observe(\.status) { [weak self] _, _ in
            Task { @MainActor in self?.heard() }
        }
        player.replaceCurrentItem(with: stream)
        player.volume = ducked ? Self.under : 1
        player.play()
        state = showing
        announce(station)
        // A stream that neither plays nor fails is one to give up on.
        after(25) { [weak self] in
            if self?.state != .playing { self?.retry() }
        }
    }

    private func build() -> AVPlayer {
        let player = AVPlayer()
        watching = [
            player.observe(\.timeControlStatus) { [weak self] _, _ in
                Task { @MainActor in self?.heard() }
            }
        ]
        self.player = player
        return player
    }

    /// The player has something to say: it is playing, it has run dry, or
    /// its stream has failed.
    private func heard() {
        guard on, !held, let player else { return }
        if player.currentItem?.status == .failed { return retry() }
        switch player.timeControlStatus {
        case .playing:
            state = .playing
            tries = 0
        case .waitingToPlayAtSpecifiedRate:
            // Run dry mid-song: the player refills by itself, and the timer
            // gives up on it if it does not.
            if state == .playing {
                state = .tuning
                after(25) { [weak self] in
                    if self?.state != .playing { self?.retry() }
                }
            }
        default:
            break
        }
    }

    /// The stream failed, ended — which for a live one means its server
    /// hung up — or never came. Three more joins, then No signal, and after
    /// that one every half minute without a word.
    private func retry() {
        guard on, !held else { return }
        tries += 1
        if tries > 3 {
            state = .lost
            player?.replaceCurrentItem(with: nil)
            turn += 1
            after(30) { [weak self] in self?.join(showing: .lost) }
        } else {
            let showing = state == .lost ? State.lost : .tuning
            state = showing
            turn += 1
            after(Double(tries) * 2) { [weak self] in self?.join(showing: showing) }
        }
    }

    /// Something to do later, unless the radio has moved on by then: been
    /// switched off, changed station, or joined again.
    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        let now = turn
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.turn == now, self.on else { return }
            work()
        }
    }

    /// Stop the stream and give the sound back — unless the voice is in the
    /// middle of a phrase, which gives it back itself when it is done.
    private func quiet() {
        turn += 1
        fade?.cancel()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        item = nil
        state = .off
        held = false
        if guide?.talking != true {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: The phone

    /// A stream that ends or fails part-way, a phone call, and the
    /// headphones coming out.
    private func listen() {
        let centre = NotificationCenter.default
        for name in [Notification.Name.AVPlayerItemFailedToPlayToEndTime, .AVPlayerItemDidPlayToEndTime] {
            centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let item = note.object as? AVPlayerItem
                Task { @MainActor in
                    guard let self, item != nil, item === self.player?.currentItem else { return }
                    self.retry()
                }
            }
        }
        centre.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let kind = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) }
            Task { @MainActor in
                guard let self, self.on else { return }
                switch kind {
                case .began:
                    self.held = true
                    self.turn += 1
                case .ended:
                    self.held = false
                    // Given back to play again, or not: a call that ended is,
                    // another app that took the sound for good is not.
                    if options?.contains(.shouldResume) == true {
                        self.tries = 0
                        self.join()
                    } else {
                        self.quiet()
                    }
                default:
                    break
                }
            }
        }
        centre.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            guard reason == .oldDeviceUnavailable else { return }
            // Headphones out: not into the street from the speaker.
            Task { @MainActor in
                guard let self, self.on else { return }
                self.quiet()
            }
        }
    }

    /// The lock screen and the buttons on a pair of headphones: play and
    /// pause, and next and previous for the station. Play starts nothing
    /// outside a ride.
    private func remote() {
        let centre = MPRemoteCommandCenter.shared()
        centre.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.open, !self.on else { return }
                self.play()
            }
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.open || self.on else { return }
                self.press()
            }
            return .success
        }
        centre.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.on else { return }
                self.step(1)
            }
            return .success
        }
        centre.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, self.on else { return }
                self.step(-1)
            }
            return .success
        }
    }

    /// The station's name on the lock screen, as a live stream: no bar to
    /// drag and no time left.
    private func announce(_ station: Station) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: "Rattatee",
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
    }
}
