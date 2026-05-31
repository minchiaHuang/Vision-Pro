import Foundation

/// A text-to-speech voice the companion can speak through.
///
/// Lets `ConversationService` treat the on-device `NarrationService` (AVSpeech)
/// and the cloud `ElevenLabsVoice` interchangeably, and fall back from one to
/// the other from a single place. Implementations drive the mascot's speaking
/// glow via `isSpeaking` and mutate it on the main queue so SwiftUI observation
/// stays happy.
protocol SpeechVoice: AnyObject {
    /// True from the moment speech is requested until it finishes or is stopped
    /// (covers any network fetch as well as playback).
    var isSpeaking: Bool { get }

    /// Speaks `text`, cancelling anything already in flight.
    func speak(_ text: String)

    /// Stops any speech immediately.
    func stop()
}

/// A cloud TTS backend (Azure / ElevenLabs) that can fail and ask the caller to
/// fall back. Lets `ConversationService` hold either backend behind one type and
/// wire the AVSpeech fallback in a single place.
protocol CloudVoice: SpeechVoice {
    /// Called on the main queue when audio can't be produced. `text` is the
    /// unspoken line; `permanent` is true for auth/quota errors that won't fix on
    /// retry, so the caller can stop routing to the cloud for the rest of the session.
    var onFailure: ((_ text: String, _ permanent: Bool) -> Void)? { get set }
}
