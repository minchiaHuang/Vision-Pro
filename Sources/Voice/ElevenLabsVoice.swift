import Foundation
import AVFAudio

/// Cloud text-to-speech via the ElevenLabs REST API (one-shot: full MP3 then play).
///
/// The primary voice for the companion when `Secrets.elevenLabsAPIKey` is set —
/// noticeably warmer than on-device `AVSpeechSynthesizer`. It does NOT own the
/// audio session (`ConversationService` owns a shared `.playAndRecord` session),
/// mirroring `NarrationService.managesAudioSession = false`.
///
/// On any failure (no key, network, HTTP, decode) it stays silent itself and
/// calls `onFailure(text)` so `ConversationService` can fall back to AVSpeech —
/// the app is never left without a voice. `isSpeaking` is set the moment
/// `speak` is called (covering the fetch as well as playback) and mutated on the
/// main queue so SwiftUI observation stays happy, like `NarrationService`.
@Observable
final class ElevenLabsVoice: NSObject, AVAudioPlayerDelegate, CloudVoice {

    /// Voice + model are single switchable constants (like `ConversationService.model`).
    /// Swap `model` to `eleven_multilingual_v2` for top quality or
    /// `eleven_flash_v2_5` for the lowest latency. Change `voiceID` to any voice
    /// from your ElevenLabs dashboard; the default is the warm "Rachel" preset.
    private static let voiceID = "21m00Tcm4TlvDq8ikWAM"
    private static let model = "eleven_turbo_v2_5"
    private static let outputFormat = "mp3_44100_128"

    private(set) var isSpeaking = false

    /// Called on the main queue when this voice can't produce audio, so the
    /// caller can fall back (to AVSpeech). `text` is the unspoken line; `permanent`
    /// is true for auth/plan errors (401/402/403) that won't fix on retry, letting
    /// the caller stop routing to the cloud for the rest of the session.
    var onFailure: ((_ text: String, _ permanent: Bool) -> Void)?

    private var player: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?

    // MARK: - SpeechVoice

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        stop()
        setSpeaking(true)

        let request: URLRequest
        do {
            request = try Self.makeRequest(text: text, key: Secrets.elevenLabsAPIKey)
        } catch {
            fail(text, permanent: true)   // missing key / bad URL won't fix on retry
            return
        }

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if Task.isCancelled { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    // 401/402/403 = bad key / missing scope / plan-blocked voice → permanent.
                    let permanent = [401, 402, 403].contains(http.statusCode)
                    self.fail(text, permanent: permanent); return
                }
                self.play(data, fallbackText: text)
            } catch {
                if Task.isCancelled { return }
                self.fail(text, permanent: false)   // network/timeout → transient, keep trying
            }
        }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        DispatchQueue.main.async {
            self.player?.stop()
            self.player = nil
            self.isSpeaking = false
        }
    }

    // MARK: - Request (pure, inspectable)

    enum TTSError: Error { case missingKey, badURL }

    private struct Body: Encodable { let text: String; let model_id: String }

    /// Builds the ElevenLabs TTS request. Pure — no I/O — so it can be reasoned
    /// about by reading (the project has no XCTest target).
    static func makeRequest(text: String, key: String,
                            voiceID: String = ElevenLabsVoice.voiceID,
                            model: String = ElevenLabsVoice.model) throws -> URLRequest {
        guard !key.isEmpty else { throw TTSError.missingKey }
        guard let url = URL(string:
            "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=\(outputFormat)")
        else { throw TTSError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("audio/mpeg", forHTTPHeaderField: "accept")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(Body(text: text, model_id: model))
        return req
    }

    // MARK: - Playback (main queue)

    private func play(_ data: Data, fallbackText: String) {
        DispatchQueue.main.async {
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                self.player = p
                p.prepareToPlay()
                if p.play() {
                    self.isSpeaking = true
                } else {
                    self.isSpeaking = false
                    self.onFailure?(fallbackText, false)   // playback hiccup → transient
                }
            } catch {
                self.isSpeaking = false
                self.onFailure?(fallbackText, false)       // decode hiccup → transient
            }
        }
    }

    private func setSpeaking(_ value: Bool) {
        DispatchQueue.main.async { self.isSpeaking = value }
    }

    /// Marks not-speaking and hands `text` to the fallback, on the main queue.
    /// `permanent` tells the caller whether to stop using the cloud this session.
    private func fail(_ text: String, permanent: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.onFailure?(text, permanent)
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isSpeaking = false
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isSpeaking = false
    }
}
