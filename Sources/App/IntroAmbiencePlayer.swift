import Foundation
import AVFAudio

/// Loops a bundled ambient bed while an intro screen is on screen. Mixes politely with any
/// other app audio, so it needs no ducking coordination. The default config drives the splash
/// `intro_ambient.m4a`; the Oops home screen passes its own bed (`home_ambient.m4a`).
///
/// The loop is *crossfaded* rather than hard-cut: two players ping-pong from the same file, and
/// each new pass fades up over the outgoing pass's tail. That overlap masks the discontinuity
/// between the file's end and start, so the short (~3.6s) beds don't click at the seam.
final class IntroAmbiencePlayer {
    private let resource: String
    private let fileExtension: String
    /// Steady-state volume. Defaults to 0.9 (the splash bed: the app's 0.6 ambient baseline +50%).
    /// `AVAudioPlayer` caps volume at 1.0, so that's as loud as a bed can go without gain staging.
    private let targetVolume: Float
    /// Short ramp from silence on the very first pass, so playback starts without a click.
    private let fadeInDuration: TimeInterval
    /// Overlap at each loop seam: the next pass fades up over this many seconds while the
    /// outgoing one fades out. Kept short so most of a brief bed plays clean, blending only the
    /// boundary. Clamped to half the file length so it still works on very short beds.
    private let crossfadeDuration: TimeInterval

    /// Two players from the same file, ping-ponged so one can fade in while the other fades out.
    private var players: [AVAudioPlayer] = []
    private var activeIndex = 0
    /// Fires `crossfadeDuration` before the active pass ends, to begin the next pass.
    private var crossfadeTimer: Timer?
    /// Pending "stop after the fade-out completes" work, so a `start()` mid-fade can cancel it.
    private var fadeOutWork: DispatchWorkItem?

    init(resource: String = "intro_ambient", fileExtension: String = "m4a",
         volume: Float = 0.9, fadeIn: TimeInterval = 1.5, crossfade: TimeInterval = 0.8) {
        self.resource = resource
        self.fileExtension = fileExtension
        self.targetVolume = volume
        self.fadeInDuration = fadeIn
        self.crossfadeDuration = crossfade
    }

    /// Starts the crossfaded loop, or resumes it if a fade-out is in flight. Idempotent: a
    /// `start()` during steady-state playback is a no-op.
    func start() {
        // Returning while fading out (e.g. back to Home from the safety page): cancel the pending
        // stop and ramp the active pass back up instead of rebuilding the players.
        if !players.isEmpty {
            fadeOutWork?.cancel()
            fadeOutWork = nil
            let active = players[activeIndex]
            if !active.isPlaying { active.currentTime = 0; active.play() }
            active.setVolume(targetVolume, fadeDuration: 0.5)
            scheduleCrossfade(forPassOf: max(0.2, active.duration - active.currentTime))
            return
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension),
              let a = try? AVAudioPlayer(contentsOf: url),
              let b = try? AVAudioPlayer(contentsOf: url)
        else { return }

        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // .playback so it's audible even with the silent switch on (this is intentional
        // ambience); .mixWithOthers so it doesn't fight the app's voice/STT sessions.
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif

        // Each pass plays once (numberOfLoops = 0); the crossfade handler hands off to the other
        // player, so looping is driven here rather than by AVAudioPlayer's hard-cut repeat.
        for p in [a, b] { p.numberOfLoops = 0; p.volume = 0; p.prepareToPlay() }
        players = [a, b]
        activeIndex = 0

        a.play()
        a.setVolume(targetVolume, fadeDuration: fadeInDuration)   // gentle ramp in on first pass
        scheduleCrossfade(forPassOf: a.duration)
    }

    /// Stops both players and cancels any pending seam / fade (e.g. when leaving the intro flow).
    func stop() {
        fadeOutWork?.cancel()
        fadeOutWork = nil
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        players.forEach { $0.stop() }
        players = []
    }

    /// Lets the loop keep playing but ramps it down to silence over `duration`, then stops — so
    /// the bed carries from Home into the safety page and settles out there rather than hard-cutting.
    /// No new crossfade passes begin during the fade. Cancelable by a later `start()`.
    func fadeOut(over duration: TimeInterval) {
        guard !players.isEmpty else { return }
        crossfadeTimer?.invalidate()   // no new passes while fading out
        crossfadeTimer = nil
        for p in players where p.isPlaying { p.setVolume(0, fadeDuration: duration) }
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        fadeOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Schedules the next crossfade to begin `crossfadeDuration` before a pass of `duration` ends.
    private func scheduleCrossfade(forPassOf duration: TimeInterval) {
        let fade = min(crossfadeDuration, duration / 2)   // never longer than half the bed
        let delay = max(0, duration - fade)
        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.crossfade()
        }
    }

    /// Brings the idle player in from silence while the active one fades out, then swaps roles
    /// and schedules the following seam. The two passes overlap for the crossfade window, so the
    /// loop point is never heard as a hard cut.
    private func crossfade() {
        guard players.count == 2 else { return }
        let incoming = players[1 - activeIndex]
        let outgoing = players[activeIndex]
        let fade = min(crossfadeDuration, incoming.duration / 2)

        incoming.currentTime = 0
        incoming.volume = 0
        incoming.play()
        incoming.setVolume(targetVolume, fadeDuration: fade)
        outgoing.setVolume(0, fadeDuration: fade)   // outgoing finishes its tail silently, then stops

        activeIndex = 1 - activeIndex
        scheduleCrossfade(forPassOf: incoming.duration)
    }
}
