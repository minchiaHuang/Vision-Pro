import Foundation
import AVFAudio

/// Fires a short, one-shot UI sound effect from a bundled file (e.g. the logo "glint" when the
/// home screen reveals its monogram). Unlike `IntroAmbiencePlayer`, this does not loop — it plays
/// the clip once and releases. Holds a strong reference for the clip's lifetime so playback isn't
/// cut short by deallocation. Mixes politely with the ambient bed and any voice/STT audio.
final class SoundEffectPlayer {
    private var player: AVAudioPlayer?

    /// Plays `resource` once from the start. A second call interrupts and restarts the effect,
    /// which is the right behaviour for a discrete cue. `volume` is 0...1 (1.0 = the file's level).
    func play(_ resource: String, fileExtension: String = "m4a", volume: Float = 1.0) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else { return }

        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // .playback so it's audible with the silent switch on; .mixWithOthers so it layers over
        // the ambient bed rather than ducking or stopping it.
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif

        let p = try? AVAudioPlayer(contentsOf: url)
        p?.volume = volume
        p?.prepareToPlay()
        p?.play()
        player = p
    }
}

/// Shared, preloaded click cue for buttons. A single `AVAudioPlayer` is decoded once (lazily on
/// first tap) and retriggered from the start each press, so the click is low-latency and adds no
/// per-button state. Wired into the shared button styles (`PrimaryPillButtonStyle`,
/// `SecondaryPillButtonStyle`, `OopsButton`), so every button built on them clicks.
enum ButtonClick {
    /// Subtle by design — UI feedback, not a foreground effect. 0...1.
    private static let volume: Float = 0.5

    private static let player: AVAudioPlayer? = {
        guard let url = Bundle.main.url(forResource: "button_click", withExtension: "m4a") else { return nil }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // .playback so it's audible with the silent switch on; .mixWithOthers so it layers over
        // ambience / voice rather than interrupting them.
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.volume = volume
        p?.prepareToPlay()
        return p
    }()

    /// Plays the click from its start. Safe to call rapidly; a new press restarts the cue.
    @MainActor static func play() {
        guard let p = player else { return }
        p.currentTime = 0
        p.play()
    }
}
