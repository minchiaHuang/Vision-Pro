import Foundation
import AVFAudio

/// Loops a gentle bundled piano track (Debussy — Clair de lune) while the visitor is in
/// the immersive gallery world. Mixes politely with any other app audio (voice/STT), so
/// it needs no ducking coordination.
///
/// Mirrors the `AVAudioPlayer` pattern used by `ElevenLabsVoice` / `NarrationService`.
final class MuseumMusicPlayer {
    /// Steady-state background volume reached after the fade-in.
    private static let targetVolume: Float = 0.6
    /// The track fades up from silence over this many seconds when playback starts.
    private static let fadeInDuration: TimeInterval = 15

    private var player: AVAudioPlayer?

    /// Starts looping playback if not already playing. Idempotent: a second `start()`
    /// while a track is in flight is a no-op. The track starts silent and ramps up to
    /// `targetVolume` over the first `fadeInDuration` seconds.
    func start() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "museum_clair_de_lune", withExtension: "mp3")
        else { return }

        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // .playback so it's audible even with the silent switch on (this is intentional
        // music); .mixWithOthers so it doesn't fight the app's voice/STT sessions.
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif

        let p = try? AVAudioPlayer(contentsOf: url)
        p?.numberOfLoops = -1                    // loop forever
        p?.volume = 0                            // start silent…
        p?.prepareToPlay()
        p?.play()
        p?.setVolume(Self.targetVolume, fadeDuration: Self.fadeInDuration)   // …ramp up over the first 15s
        player = p
    }

    /// Stops playback and releases the player (e.g. when leaving the gallery).
    func stop() {
        player?.stop()
        player = nil
    }
}
