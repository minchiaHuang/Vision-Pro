import Foundation
import Speech
import AVFAudio

/// Phase 6b — live speech-to-text using Apple's on-device Speech framework.
///
/// Captures microphone audio with `AVAudioEngine` and streams it to
/// `SFSpeechRecognizer`, preferring on-device recognition when available (lower
/// latency, better privacy). It does NOT configure the audio session itself —
/// `ConversationService` owns a shared `.playAndRecord` session so recording and
/// TTS playback don't fight each other.
@Observable
final class SpeechRecognizer {

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var transcript = ""
    private(set) var isListening = false

    enum STTError: Error { case unauthorized, unavailable }

    /// Requests speech-recognition + microphone authorization. Returns true only
    /// if BOTH are granted. Triggers the system permission prompts on first call.
    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    /// Starts live transcription. The caller must have already activated a
    /// record-capable audio session. Throws if the recognizer is unavailable.
    func start() throws {
        guard let recognizer, recognizer.isAvailable else { throw STTError.unavailable }

        task?.cancel()
        task = nil
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            Task { @MainActor in self.transcript = text }
        }
    }

    /// Stops capture and returns the best transcript collected so far.
    @discardableResult
    func stop() -> String {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        return transcript
    }
}
