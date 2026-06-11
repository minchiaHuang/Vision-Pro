import Foundation
import AVFAudio

/// Loops the bundled world soundtrack (`museum_clair_de_lune.mp3`) while the visitor is in
/// the world — the immersive gallery on visionOS and the full-screen world on iOS. Mixes
/// politely with any other app audio (voice/STT), so it needs no ducking coordination.
///
/// Mirrors the `AVAudioPlayer` pattern used by `ElevenLabsVoice` / `NarrationService`.
final class MuseumMusicPlayer {
    /// Steady-state target volume (0–1) the track fades up to. Set before `start()` to pick the
    /// fade-in target; `setVolume` changes it live (no fade). Default 30%.
    var volume: Float = 0.3
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
        p?.setVolume(volume, fadeDuration: Self.fadeInDuration)   // …ramp up over the first 15s
        player = p
    }

    /// Live volume change (e.g. the settings slider) — applies immediately, no fade.
    func setVolume(_ v: Float) {
        volume = v
        player?.volume = v
    }

    /// Stops playback and releases the player (e.g. when leaving the gallery).
    func stop() {
        player?.stop()
        player = nil
    }
}
