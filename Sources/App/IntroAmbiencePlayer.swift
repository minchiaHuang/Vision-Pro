import Foundation
import AVFAudio

/// Loops the bundled ambient bed (`intro_ambient.m4a`) while the opening splash screen is
/// on screen. Mixes politely with any other app audio, so it needs no ducking coordination.
///
/// Mirrors the `AVAudioPlayer` pattern used by `MuseumMusicPlayer` / `ElevenLabsVoice`.
final class IntroAmbiencePlayer {
    /// Steady-state volume. 0.9 = the app's standard ambient level (0.6, set by the world
    /// soundtrack) raised by 50%, so the intro bed is noticeably more present. `AVAudioPlayer`
    /// caps volume at 1.0, so this is as loud as the bed can go without gain staging.
    private static let targetVolume: Float = 0.9
    /// Short ramp from silence so playback starts without an audible click.
    private static let fadeInDuration: TimeInterval = 1.5

    private var player: AVAudioPlayer?

    /// Starts looping playback if not already playing. Idempotent: a second `start()` while a
    /// track is in flight is a no-op.
    func start() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "intro_ambient", withExtension: "m4a")
        else { return }

        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // .playback so it's audible even with the silent switch on (this is intentional
        // ambience); .mixWithOthers so it doesn't fight the app's voice/STT sessions.
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif

        let p = try? AVAudioPlayer(contentsOf: url)
        p?.numberOfLoops = -1                    // loop forever
        p?.volume = 0                            // start silent…
        p?.prepareToPlay()
        p?.play()
        p?.setVolume(Self.targetVolume, fadeDuration: Self.fadeInDuration)   // …ramp up to avoid a click
        player = p
    }

    /// Stops playback and releases the player (e.g. when leaving the splash for the quiz).
    func stop() {
        player?.stop()
        player = nil
    }
}
