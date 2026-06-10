#if os(visionOS)
import SwiftUI

/// Floating AI voice companion shown alongside the Oops 6DoF splat world.
///
/// A vertical glass pill: X (exit world) · amber orb (tap to talk) · replay arrow.
/// Invisible while the splat is loading (.plain window style hides Color.clear);
/// appears once SplatSession reaches .ready and auto-speaks a welcome.
///
/// Exit delegates to SplatSession.requestExit() → OopsWorldControls.performExit()
/// so the immersive-space dismiss + window cleanup stays in one place.
struct OopsVoiceOrbView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var session = SplatSession.shared
    @State private var convo = ConversationService()
    @State private var started = false

    private let welcomeText = "Welcome. I'll be here with you while you explore. Tap the orb whenever you want to talk."

    var body: some View {
        Group {
            switch session.phase {
            case .ready:
                pillContent
            default:
                Color.clear
            }
        }
        .task(id: session.phase) {
            switch session.phase {
            case .idle:
                try? await Task.sleep(for: .milliseconds(400))
                if session.phase == .idle { dismissWindow(id: "oops-voice-orb") }
            case .ready:
                guard !started else { return }
                started = true
                appState.loadDefaultWorld()
                let world  = appState.world      ?? WorldCatalog.fallback
                let scores = appState.axisScores ?? .neutral
                let params = appState.worldParams ?? WorldMapper.map(scores)
                convo.configure(world: world, scores: scores, params: params, hopeFreeText: "")
                try? await Task.sleep(for: .milliseconds(600))
                convo.speakEntry(welcomeText)
            default:
                break
            }
        }
        .onDisappear { convo.stop() }
    }

    private var pillContent: some View {
        VStack(spacing: 0) {
            // visionOS: .hoverEffect() is required so eye tracking recognises the
            // hit target and the user can pinch to activate. .buttonStyle(.plain)
            // alone removes the system hover highlight, making buttons unreachable.
            Button { session.requestExit() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 60, height: 80)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()

            Spacer()

            Button(action: tap) {
                OrbView(size: 80, isSpeaking: convo.isSpeaking, isListening: convo.isListening)
            }
            .buttonStyle(.plain)
            .hoverEffect()

            Spacer()

            Button { convo.speakEntry(welcomeText) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 60, height: 80)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()
        }
        .frame(width: 180, height: 420)
    }

    private func tap() {
        if convo.isListening {
            convo.finishListeningAndReply()
        } else if convo.turn == .idle {
            Task { await convo.beginListening() }
        }
    }
}

// MARK: - Future Museum Curator orb

/// Floating Curator voice for the Future Museum gallery — the gallery path's counterpart to
/// `OopsVoiceOrbView` (which is gated on `SplatSession`). The gallery RealityKit space is ready
/// the moment it opens, so this pill appears immediately. It drives the SHARED
/// `AppState.museumConversation` (also used by the in-gallery proximity narrator), so per-beat
/// narration and push-to-talk never overlap. Exit lives on the gallery controls panel, so the
/// pill is just: replay · orb (tap to talk).
struct MuseumVoiceOrbView: View {
    @Environment(AppState.self) private var appState

    private let welcomeText = "Welcome. Walk slowly. Each room is a part of the path you asked about — most of it is its cost. Talk to me whenever you want to."

    private var convo: ConversationService? { appState.museumConversation }

    var body: some View {
        Group {
            if let convo {
                pill(convo)
            } else {
                Color.clear
            }
        }
        // The gallery opens silent — no auto-welcome. The user starts any conversation by
        // tapping the orb; the replay arrow re-speaks the welcome on demand.
        .onDisappear { convo?.stop() }
    }

    private func pill(_ convo: ConversationService) -> some View {
        VStack(spacing: 0) {
            Button { convo.speakEntry(welcomeText) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 60, height: 80)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()

            Spacer()

            Button { tap(convo) } label: {
                OrbView(size: 80, isSpeaking: convo.isSpeaking, isListening: convo.isListening)
            }
            .buttonStyle(.plain)
            .hoverEffect()

            Spacer().frame(height: 40)
        }
        .frame(width: 180, height: 360)
    }

    private func tap(_ convo: ConversationService) {
        if convo.isListening {
            convo.finishListeningAndReply()
        } else if convo.turn == .idle {
            Task { await convo.beginListening() }
        }
    }
}

// MARK: - Previews (bypass phase/session — show pill directly)

#Preview("Pill — Idle") {
    OopsVoicePillPreview(isSpeaking: false, isListening: false)
}
#Preview("Pill — Listening") {
    OopsVoicePillPreview(isSpeaking: false, isListening: true)
}
#Preview("Pill — Speaking") {
    OopsVoicePillPreview(isSpeaking: true, isListening: false)
}

private struct OopsVoicePillPreview: View {
    var isSpeaking: Bool
    var isListening: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 60, height: 80)
            Spacer()
            OrbView(size: 80, isSpeaking: isSpeaking, isListening: isListening)
            Spacer()
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 60, height: 80)
        }
        .frame(width: 180, height: 420)
        .preferredColorScheme(.dark)
    }
}
#endif
