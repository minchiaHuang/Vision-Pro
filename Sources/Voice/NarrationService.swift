import Foundation
import AVFAudio

/// Phase 6a — the world's voice companion (mascot) entry narration.
///
/// Wraps `AVSpeechSynthesizer` for **on-device TTS output only**: no microphone,
/// no speech recognition, no network, and therefore no permission prompts. This
/// is the seed of the planned Phase 6b `ConversationService` (mic → STT → cloud
/// LLM → TTS), which will reuse this as its text-to-speech stage rather than
/// renaming it.
@Observable
final class NarrationService: NSObject, AVSpeechSynthesizerDelegate, SpeechVoice {

    private let synth = AVSpeechSynthesizer()

    /// True while an utterance is being spoken. Drives the mascot's speaking
    /// animation. Mutated on the main queue so SwiftUI observation stays happy.
    private(set) var isSpeaking = false

    /// When true (default), `speak()` configures a `.playback` audio session each
    /// time. Phase 6b's `ConversationService` sets this false and owns a shared
    /// `.playAndRecord` session, so TTS playback and mic capture don't clobber
    /// each other.
    var managesAudioSession = true

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Speaks `text` once, cancelling any utterance already in flight. Configures
    /// a spoken-audio playback session so the guide is audible even with the
    /// hardware silent switch on.
    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        configureSession()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94   // a touch slower, warmer
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2
        synth.speak(utterance)
    }

    /// Stops any narration immediately (e.g. on "Start over" or leaving the world).
    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    // MARK: - Audio session

    private func configureSession() {
        guard managesAudioSession else { return }
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        #endif
    }

    /// Best available English voice: prefer a premium/enhanced quality voice when
    /// the user has one installed, else fall back to the system default.
    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        if let premium = english.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = english.first(where: { $0.quality == .enhanced }) { return enhanced }
        return AVSpeechSynthesisVoice(language: "en-US") ?? english.first
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}
