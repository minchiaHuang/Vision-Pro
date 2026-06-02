import Foundation
import AVFAudio

/// Phase 6b — the world's two-way voice companion.
///
/// Orchestrates the loop: microphone → speech-to-text (`SpeechRecognizer`) →
/// cloud Claude (Messages API over plain `URLSession`, mirroring
/// `WorldLabsService`) → text-to-speech (reuses 6a's `NarrationService`).
///
/// It owns the audio session for the whole conversation so recording and
/// playback don't clobber each other, and grounds Claude in THIS world's hidden
/// scores so the guide talks about what the visitor is actually seeing — the
/// Route-D ability a black-box AI world can't offer.
@Observable
@MainActor
final class ConversationService {

    enum Turn { case idle, listening, thinking, speaking }

    private(set) var turn: Turn = .idle
    private(set) var lastError: String?

    private let stt = SpeechRecognizer()
    /// On-device AVSpeech voice — always available; the fallback for all output.
    let narrator: NarrationService
    /// Cloud voice — the primary output when a key is present, else nil.
    /// Azure is preferred over ElevenLabs when both keys are set.
    private let cloud: (any CloudVoice)?
    /// Circuit breaker: set once the cloud voice hits a permanent error (bad key /
    /// missing scope / plan-blocked voice), so we stop wasting a failing round-trip
    /// on every line and use AVSpeech directly for the rest of the session.
    private var cloudDisabled = false

    private var systemPrompt = ""
    private var history: [Message] = []

    /// Conversation model. Single switchable constant — change to
    /// `"claude-sonnet-4-6"` for richer (slower) replies.
    private static let model = "claude-haiku-4-5-20251001"

    init() {
        let n = NarrationService()
        n.managesAudioSession = false   // ConversationService owns the audio session
        self.narrator = n

        // Cloud TTS is the primary voice when a key is set (Azure preferred, else
        // ElevenLabs); otherwise pure AVSpeech. Its `onFailure` hands the unspoken
        // text back so we fall back to AVSpeech — the guide is never left silent
        // (no key / no network / quota exhausted).
        if !Secrets.azureSpeechKey.isEmpty {
            self.cloud = AzureVoice()
        } else if !Secrets.elevenLabsAPIKey.isEmpty {
            self.cloud = ElevenLabsVoice()
        } else {
            self.cloud = nil
        }
        cloud?.onFailure = { [weak self] text, permanent in
            guard let self else { return }
            if permanent { self.cloudDisabled = true }   // stop retrying the cloud this session
            self.narrator.speak(text)
        }
    }

    /// True while the guide is talking (cloud or AVSpeech) — drives the speaking glow.
    var isSpeaking: Bool { (cloud?.isSpeaking ?? false) || narrator.isSpeaking }
    /// True while listening for the visitor — drives the mascot's listening ring.
    var isListening: Bool { turn == .listening }

    // MARK: - Setup

    /// Grounds the guide in this specific world. Call once when the world appears.
    func configure(world: World, scores: AxisScores, params: WorldParams, hopeFreeText: String) {
        systemPrompt = Self.makeSystemPrompt(world: world, scores: scores,
                                             params: params, hopeFreeText: hopeFreeText)
    }

    /// Speaks the 6a entry narration through the shared TTS voice.
    func speakEntry(_ text: String) {
        activatePlaybackSession()
        routeSpeak(text)
    }

    /// Routes spoken output through the cloud voice when available, else AVSpeech.
    /// The cloud voice falls back to AVSpeech on failure via its `onFailure` hook.
    private func routeSpeak(_ text: String) {
        if let cloud, !cloudDisabled { cloud.speak(text) } else { narrator.speak(text) }
    }

    /// Stops whichever voice is currently talking.
    private func stopSpeaking() {
        cloud?.stop()
        narrator.stop()
    }

    // MARK: - Push-to-talk

    /// Starts listening to the visitor (tap the mascot). Requests mic + speech
    /// permission on first use.
    func beginListening() async {
        guard turn == .idle else { return }
        lastError = nil
        stopSpeaking()
        guard await stt.requestAuthorization() else {
            lastError = "Microphone or speech permission is needed to talk with your guide."
            return
        }
        do {
            try activateRecordSession()
            try stt.start()
            turn = .listening
        } catch {
            lastError = "Could not start listening."
            turn = .idle
        }
    }

    /// Stops listening, sends the transcript to Claude, and speaks the reply.
    func finishListeningAndReply() {
        guard turn == .listening else { return }
        let text = stt.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { turn = .idle; return }

        turn = .thinking
        history.append(Message(role: "user", content: text))
        Task {
            do {
                let reply = try await send()
                history.append(Message(role: "assistant", content: reply))
                // Back to idle so a tap can barge in; `isSpeaking` drives the
                // mascot's speaking glow while the reply is read aloud.
                turn = .idle
                activatePlaybackSession()
                routeSpeak(reply)
            } catch {
                lastError = Self.describe(error)
                turn = .idle
            }
        }
    }

    /// Fully stops the conversation (leaving the world / starting over).
    func stop() {
        stt.stop()
        stopSpeaking()
        deactivateSession()
        turn = .idle
    }

    // MARK: - Claude (Messages API over URLSession)

    private struct Message: Codable { let role: String; let content: String }

    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }

    enum ConvError: Error { case missingKey, http(String), empty }

    private func send() async throws -> String {
        let key = Secrets.anthropicAPIKey
        guard !key.isEmpty else { throw ConvError.missingKey }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            Request(model: Self.model, max_tokens: 300, system: systemPrompt, messages: history)
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ConvError.http("HTTP \(http.statusCode): \(body.prefix(200))")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined(separator: " ")
        guard !text.isEmpty else { throw ConvError.empty }
        return text
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case ConvError.missingKey: return "Add an Anthropic API key in Secrets.swift to talk with your guide."
        default: return "The guide couldn't answer just now."
        }
    }

    // MARK: - Audio session

    private func activatePlaybackSession() {
        #if !os(macOS)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? s.setActive(true)
        #endif
    }

    private func activateRecordSession() throws {
        #if !os(macOS)
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .spokenAudio,
                          options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try s.setActive(true)
        #endif
    }

    private func deactivateSession() {
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Grounded system prompt (research direction 4 tone)

    private static func makeSystemPrompt(world: World, scores: AxisScores,
                                         params: WorldParams, hopeFreeText: String) -> String {
        func lean(_ v: Double, _ low: String, _ high: String) -> String { v < 0.5 ? low : high }
        let leanings = [
            lean(scores.autonomyBelonging, "values space of their own", "is drawn toward closeness with others"),
            lean(scores.exploreStable, "leans toward wandering and the open horizon", "leans toward steadiness and shelter"),
            lean(scores.expressionConnection, "leans toward their own voice", "leans toward shared, living things"),
            lean(scores.calmVivid, "leans toward calm and quiet", "leans toward aliveness and energy")
        ].joined(separator: ", ")

        let hope: String
        switch scores.hope {
        case .ownPath: hope = "being more at ease as themselves"
        case .people:  hope = "drawing a little closer to others"
        case .explore: hope = "daring to wander further out"
        case .stable:  hope = "finding firmer, steadier ground"
        }

        let scene = PromptBuilder.prompt(from: params, archetypeName: world.title)
        let ownWords = hopeFreeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : " In their own words, they hope for: \"\(hopeFreeText)\"."

        return """
        You are a warm, unhurried voice companion who lives inside the visitor's personal world, "\(world.title)". \(world.blurb)
        This world was shaped from how they answered a short reflection. The visitor \(leanings). The direction they said they're moving toward is \(hope).\(ownWords)
        The world looks and feels like: \(scene).
        Speak about THIS world and what it gently reflects in them. Strict tone rules: never say "should" or "must"; frame everything as a direction they are moving toward, never a flaw or a lack; invite rather than instruct. Keep every reply to 2-3 short spoken sentences — it will be read aloud. End with one gentle, open question that helps them notice what feels true. Never mention scores, axes, parameters, or that this is an app or a quiz.
        """
    }
}
