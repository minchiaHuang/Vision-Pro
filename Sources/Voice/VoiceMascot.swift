import SwiftUI

/// The shared voice-companion mascot: a tappable `OrbView` with a status caption, an
/// error line, and the full push-to-talk lifecycle. Owns its own `ConversationService`,
/// so every screen that shows a guide (`iOSWorldView`, `VisionWorldPanel`,
/// `VoiceTestView`) drives it the same way.
///
/// - tap: push-to-talk (start listening → send the turn)
/// - long-press: replay the welcome narration
/// - on appear: `configure` the guide, then speak `welcome()` once after `autoSpeakDelay`
/// - on disappear: stop the conversation
struct VoiceMascot: View {
    var size: CGFloat = 96
    /// True when the mascot sits on top of imagery (the world) and needs a high-contrast
    /// caption; false for warm/glass surfaces where `.secondary` reads fine.
    var onContentBackground: Bool = false
    var autoSpeakDelay: Duration = .milliseconds(800)
    /// Grounds the guide in a specific world. Called once before the welcome is spoken.
    let configure: (ConversationService) -> Void
    /// Entry / replay narration text. Return nil to skip auto-speak.
    let welcome: () -> String?

    @State private var convo = ConversationService()
    @State private var started = false

    var body: some View {
        VStack(spacing: 6) {
            OrbView(size: size,
                    isSpeaking: convo.isSpeaking,
                    isListening: convo.isListening)
                .contentShape(Circle())
                .onTapGesture { tap() }
                .onLongPressGesture { replay() }
                .accessibilityLabel("Talk with your world's guide")

            Text(caption)
                .font(onContentBackground ? .caption2 : .caption)
                .foregroundStyle(onContentBackground ? AnyShapeStyle(.white.opacity(0.7))
                                                      : AnyShapeStyle(.secondary))
                .shadow(radius: onContentBackground ? 4 : 0)

            if let err = convo.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .shadow(radius: onContentBackground ? 4 : 0)
            }
        }
        .task {
            guard !started else { return }
            started = true
            configure(convo)
            try? await Task.sleep(for: autoSpeakDelay)
            if let text = welcome() { convo.speakEntry(text) }
        }
        .onDisappear { convo.stop() }
    }

    /// Short tap = push-to-talk (start listening / send the turn).
    private func tap() {
        if convo.isListening {
            convo.finishListeningAndReply()
        } else if convo.turn == .idle {
            Task { await convo.beginListening() }
        }
    }

    /// Long-press replays the welcome narration.
    private func replay() {
        if let text = welcome() { convo.speakEntry(text) }
    }

    /// One-line status shown under the orb.
    private var caption: String {
        switch convo.turn {
        case .listening: return "Listening… tap to send"
        case .thinking:  return "Thinking…"
        case .speaking:  return "Speaking…"
        case .idle:      return convo.isSpeaking ? "Speaking…" : "Tap to talk"
        }
    }
}
