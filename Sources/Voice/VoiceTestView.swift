import SwiftUI

// ⚠️ DEV / VERIFICATION ONLY — do NOT ship.
// Standalone entry for the AI voice companion, reached via the `Voice` scheme
// (LAUNCH_FEATURE=voice). See LaunchRouter. In the real app the voice feature
// lives inside the world (WorldView); this screen drives the same
// `ConversationService` in isolation so it can be tested without the quiz/world.
struct VoiceTestView: View {
    @State private var convo = ConversationService()
    @State private var configured = false

    /// A neutral preset so the guide has a world/persona to ground its replies.
    private let world = WorldCatalog.world(for: .cozyCommunal)
    private let scores = AxisScores.neutral

    var body: some View {
        ZStack {
            WarmBackground()

            VStack(spacing: 28) {
                Eyebrow("Voice Companion — test")

                OrbView(size: 140,
                        isSpeaking: convo.isSpeaking,
                        isListening: convo.isListening)
                    .contentShape(Circle())
                    .onTapGesture { tapMascot() }
                    .onLongPressGesture { replayWelcome() }
                    .accessibilityLabel("Tap to talk, long-press to replay the welcome")

                Text(statusCaption)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Tap the orb to talk · long-press to replay the welcome")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let err = convo.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
            .padding(40)
        }
        .onAppear {
            guard !configured else { return }
            let params = WorldMapper.map(scores)
            convo.configure(world: world, scores: scores, params: params, hopeFreeText: "")
            convo.speakEntry("Hi — I'm your guide. Tap the orb and say something to test the voice.")
            configured = true
        }
        .onDisappear { convo.stop() }
    }

    /// Short tap = push-to-talk (start listening / send the turn).
    private func tapMascot() {
        if convo.isListening {
            convo.finishListeningAndReply()
        } else if convo.turn == .idle {
            Task { await convo.beginListening() }
        }
    }

    private func replayWelcome() {
        convo.speakEntry("Hi again — tap the orb and say something to test the voice.")
    }

    private var statusCaption: String {
        switch convo.turn {
        case .idle:      return "Idle"
        case .listening: return "Listening…"
        case .thinking:  return "Thinking…"
        case .speaking:  return "Speaking…"
        }
    }
}
