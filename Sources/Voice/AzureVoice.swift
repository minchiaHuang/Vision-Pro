import Foundation
import AVFAudio
import os

/// Diagnostic log for the Azure TTS path (filter the Xcode console by category "Voice").
private let azureLog = Logger(subsystem: "VisitingArtisan", category: "Voice")

/// Cloud text-to-speech via the Azure Speech REST API (one-shot: full MP3 then play).
///
/// The primary voice when `Secrets.azureSpeechKey` is set — natural neural voices
/// on Azure's always-free F0 tier (500k chars/month). Same shape as
/// `ElevenLabsVoice`: it does NOT own the audio session (`ConversationService`
/// owns `.playAndRecord`), and on any failure it stays silent and calls
/// `onFailure(text, permanent)` so the caller can fall back to AVSpeech.
@Observable
final class AzureVoice: NSObject, AVAudioPlayerDelegate, CloudVoice {

    /// Region + voice are single switchable constants. The region must match the
    /// Azure Speech resource ("southeastasia"). Swap `voice` to any Azure neural
    /// voice (e.g. "en-US-JennyNeural", "en-US-AriaNeural"); the default is the
    /// warm "Ava" voice.
    private static let region = "southeastasia"
    private static let voice = "en-US-AvaNeural"
    private static let outputFormat = "audio-24khz-96kbitrate-mono-mp3"

    private(set) var isSpeaking = false

    /// Called on the main queue when this voice can't produce audio (see `CloudVoice`).
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
            request = try Self.makeRequest(text: text, key: Secrets.azureSpeechKey)
        } catch {
            fail(text, permanent: true)
            return
        }

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if Task.isCancelled { return }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    // 400/401/403 = bad request / bad key / forbidden → permanent.
                    let permanent = [400, 401, 403].contains(http.statusCode)
                    self.fail(text, permanent: permanent); return
                }
                self.play(data, fallbackText: text)
            } catch {
                if Task.isCancelled { return }
                self.fail(text, permanent: false)   // network/timeout → transient
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

    /// Builds the Azure Speech TTS request (SSML body). Pure — no I/O — so it can
    /// be reasoned about by reading (the project has no XCTest target).
    static func makeRequest(text: String, key: String,
                            region: String = AzureVoice.region,
                            voice: String = AzureVoice.voice) throws -> URLRequest {
        guard !key.isEmpty else { throw TTSError.missingKey }
        guard let url = URL(string:
            "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")
        else { throw TTSError.badURL }

        let ssml = """
        <speak version='1.0' xml:lang='en-US'><voice xml:lang='en-US' name='\(voice)'>\(escapeXML(text))</voice></speak>
        """

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        req.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        req.setValue(outputFormat, forHTTPHeaderField: "X-Microsoft-OutputFormat")
        req.setValue("VisitingArtisan", forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(ssml.utf8)
        return req
    }

    /// Escapes the five XML special characters so the spoken text can't break the SSML.
    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
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
                    self.onFailure?(fallbackText, false)
                }
            } catch {
                self.isSpeaking = false
                self.onFailure?(fallbackText, false)
            }
        }
    }

    private func setSpeaking(_ value: Bool) {
        DispatchQueue.main.async { self.isSpeaking = value }
    }

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
