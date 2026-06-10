import Foundation
import AVFAudio
import os

/// Logs which voice backend is in use and why it falls back, so a robotic-sounding build
/// can be diagnosed from the Xcode console (filter by category "Voice").
private let voiceLog = Logger(subsystem: "VisitingArtisan", category: "Voice")

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
    /// The exhibit currently being generated/spoken via a wall-plaque play button. All plaques
    /// share this one service, so each plaque shows its busy/speaking state only while this equals
    /// its own beat id. nil whenever no play-to-describe is in flight.
    private(set) var activeBeatID: String?

    /// The line currently being spoken (entry / narration / play-to-describe). Drives the optional
    /// on-plaque subtitle. nil whenever nothing is being spoken.
    private(set) var spokenLine: String?

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
    private var history: [AnthropicClient.ChatMessage] = []
    /// The in-flight play-to-describe task (plaque play button). Held so a second tap can cancel
    /// generation/playback mid-way.
    private var describeTask: Task<Void, Never>?

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
            voiceLog.info("Voice backend = Azure (key present)")
        } else if !Secrets.elevenLabsAPIKey.isEmpty {
            self.cloud = ElevenLabsVoice()
            voiceLog.info("Voice backend = ElevenLabs (key present)")
        } else {
            self.cloud = nil
            voiceLog.warning("Voice backend = AVSpeech only (no cloud key) — voice will sound robotic. Add AZURE_SPEECH_KEY or ELEVEN_LABS_API_KEY to the build (~/.config/visualeyes/keys.plist or a scheme env var).")
        }
        cloud?.onFailure = { [weak self] text, permanent in
            guard let self else { return }
            if permanent { self.cloudDisabled = true }   // stop retrying the cloud this session
            voiceLog.error("Cloud voice failed (permanent=\(permanent, privacy: .public)) → falling back to AVSpeech")
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

    /// Grounds the guide as the Future Museum's "Curator" — documentary tone, anchored in the
    /// generated story + the visitor's own answers. Call once when the museum opens.
    func configureCurator(story: MuseumStory, answers: MuseumAnswers) {
        systemPrompt = Self.makeCuratorPrompt(story: story, answers: answers)
    }

    /// Speaks the 6a entry narration through the shared TTS voice.
    func speakEntry(_ text: String) {
        activatePlaybackSession()
        routeSpeak(text)
    }

    /// Speaks a beat's narration through the shared voice (interrupting any current line). Used
    /// by the in-museum proximity narrator so narration and push-to-talk share one audio session.
    func narrate(_ text: String) {
        stopSpeaking()
        activatePlaybackSession()
        routeSpeak(text)
    }

    /// Routes spoken output through the cloud voice when available, else AVSpeech.
    /// The cloud voice falls back to AVSpeech on failure via its `onFailure` hook.
    private func routeSpeak(_ text: String) {
        spokenLine = text
        if let cloud, !cloudDisabled { cloud.speak(text) } else { narrator.speak(text) }
    }

    /// Stops whichever voice is currently talking.
    private func stopSpeaking() {
        cloud?.stop()
        narrator.stop()
        spokenLine = nil
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
        history.append(AnthropicClient.ChatMessage(role: "user", content: text))
        Task {
            do {
                let reply = try await send()
                history.append(AnthropicClient.ChatMessage(role: "assistant", content: reply))
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
        describeTask?.cancel()
        describeTask = nil
        stt.stop()
        stopSpeaking()
        deactivateSession()
        turn = .idle
        activeBeatID = nil
    }

    // MARK: - Play-to-describe (wall-plaque play/stop toggle)

    /// Play/stop toggle for a wall-plaque button. First tap: the Curator generates a FRESH spoken
    /// description for THIS exhibit and speaks it (the plaque shows a "playing" animation). Tapping
    /// the SAME plaque again stops it immediately — even mid-generation; tapping a DIFFERENT plaque
    /// switches to it. A model failure falls back to the curated `narration` so the plaque is never
    /// silent. One-shot: it never appends to the push-to-talk `history`, and won't barge into a mic
    /// turn.
    func toggleDescribe(_ beat: MuseumNode) {
        // Second tap on the playing/loading plaque → stop.
        if activeBeatID == beat.id { stopDescribe(); return }
        // Don't interrupt an active push-to-talk (mic) turn.
        guard turn != .listening else { return }
        // Stop any other plaque that's mid-describe, then start this one.
        stopDescribe()
        lastError = nil
        turn = .thinking
        activeBeatID = beat.id
        describeTask = Task { [weak self] in
            guard let self else { return }
            let line: String
            do {
                line = try await self.claude.reply(
                    system: self.systemPrompt,
                    history: [AnthropicClient.ChatMessage(
                        role: "user", content: Self.describeExhibitMessage(beat: beat))]
                )
            } catch {
                if Task.isCancelled { return }
                self.lastError = Self.describe(error)
                line = beat.narration   // never leave the plaque silent
            }
            if Task.isCancelled { return }
            self.activatePlaybackSession()
            self.turn = .speaking
            self.routeSpeak(line)
            await self.waitUntilSpeechEnds()
            if Task.isCancelled { return }
            self.turn = .idle
            self.activeBeatID = nil
            self.describeTask = nil
        }
    }

    /// Stops the in-flight play-to-describe (cancels generation, silences playback) and returns the
    /// plaque button to its resting "Play" state.
    func stopDescribe() {
        describeTask?.cancel()
        describeTask = nil
        stopSpeaking()
        turn = .idle
        activeBeatID = nil
    }

    /// Awaits the start (cloud fetch / TTS warm-up) then the end of the current spoken line, so the
    /// caller can return the plaque button to "Play" once playback finishes on its own. Polls the
    /// observable `isSpeaking`; cancellation-aware (a stop tap cancels the task).
    private func waitUntilSpeechEnds() async {
        var warmup = 0
        while !isSpeaking && warmup < 60 {            // up to ~6s for playback to begin
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
            warmup += 1
        }
        while isSpeaking {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }
    }

    // MARK: - Claude (Messages API over URLSession)

    /// Error surface for the conversation; `describe(_:)` and callers pattern-match on it.
    enum ConvError: Error { case missingKey, http(String), empty }

    /// Claude client. Default talks to the real API with the key from `Secrets`;
    /// `AnthropicClient` is independently injectable/testable (stubbed `URLSession`).
    private let claude = AnthropicClient()

    private func send() async throws -> String {
        try await claude.reply(system: systemPrompt, history: history)
    }

    static func describe(_ error: Error) -> String {
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

    static func makeSystemPrompt(world: World, scores: AxisScores,
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

    // MARK: - Curator prompt (Future Museum)

    /// Grounds the guide as the documentary "Curator" of the visitor's five-room future museum,
    /// anchored in the generated story's beats + the visitor's own fear/sacrifice/worthIt and the
    /// closing decision. Blank answer fields are simply omitted (worthIt is usually blank — the
    /// Curator infers it).
    static func makeCuratorPrompt(story: MuseumStory, answers: MuseumAnswers) -> String {
        let beats = story.nodes
            .map { "- \($0.stage) (age \($0.age)): \($0.narration)" }
            .joined(separator: "\n")
        let visitorBits = [
            answers.fear.isEmpty ? nil : "their fear is \"\(answers.fear)\"",
            answers.sacrifice.isEmpty ? nil : "what they are least willing to give up is \"\(answers.sacrifice)\"",
            answers.worthIt.isEmpty ? nil : "what would make it worth it is \"\(answers.worthIt)\""
        ].compactMap { $0 }.joined(separator: ", ")
        let visitorLine = visitorBits.isEmpty ? "" : "The visitor told you \(visitorBits). "
        return """
        You are "The Curator" of a five-room museum about one visitor's possible future as \(story.persona). You speak like a documentary narrator — short, plain, second-person, never motivational, never sentimental, no slogans, no exclamation marks. The exhibition shows that path honestly, mostly its cost.
        The five rooms on the walls are:
        \(beats)
        \(visitorLine)The closing question at the exit is: "\(story.decision_prompt)"
        When the visitor speaks to you, answer about THIS exhibition and what it asks of them. Keep every reply to 2-3 short spoken sentences — it is read aloud. Persuade neither toward nor away from the path; hand the choice back to them. Never mention that this is an app, a quiz, or AI.
        """
    }

    /// The synthetic "visitor turn" that asks the Curator to describe ONE exhibit afresh, sent by
    /// the wall-plaque play button. Pure + static so the wording is unit-testable (mirrors the
    /// prompt builders above). The `systemPrompt` already grounds the Curator in all five beats;
    /// this just points at the one in front of the visitor and asks for new words, not the label.
    static func describeExhibitMessage(beat: MuseumNode) -> String {
        let stage = beat.stage.replacingOccurrences(of: "_", with: " ")
        return """
        I'm standing in front of one exhibit now: "\(beat.caption)" — the \(stage) room, age \(beat.age). \
        Describe THIS room and what it asks of me, in your own Curator voice. Do not repeat the wall text word for word — say it anew. Keep it to 2-3 short spoken sentences.
        """
    }
}

// MARK: - Anthropic Messages API client

/// Thin Claude Messages API client over plain `URLSession`. Split out of
/// `ConversationService` so the HTTP path is testable in isolation (no audio session,
/// stubbed `URLSession`) — `ConversationService` just owns one and feeds it the prompt.
struct AnthropicClient {

    /// One conversation turn. `role` is "user" / "assistant".
    struct ChatMessage: Codable { let role: String; let content: String }

    var apiKey: String = Secrets.anthropicAPIKey
    var session: URLSession = .shared
    /// Conversation model — change to `"claude-sonnet-4-6"` for richer (slower) replies.
    var model: String = "claude-haiku-4-5-20251001"
    var maxTokens: Int = 300

    /// Sends the grounded system prompt + history and returns the assistant's text.
    /// Throws `ConversationService.ConvError` on a missing key, HTTP error, or empty reply.
    func reply(system: String, history: [ChatMessage]) async throws -> String {
        guard !apiKey.isEmpty else { throw ConversationService.ConvError.missingKey }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            Request(model: model, max_tokens: maxTokens, system: system, messages: history)
        )

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ConversationService.ConvError.http("HTTP \(http.statusCode): \(body.prefix(200))")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined(separator: " ")
        guard !text.isEmpty else { throw ConversationService.ConvError.empty }
        return text
    }

    private struct Request: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [ChatMessage]
    }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
    }
}
