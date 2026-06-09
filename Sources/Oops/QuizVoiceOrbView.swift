#if os(visionOS)
import SwiftUI
import AVFAudio

/// Floating speech-to-text orb shown beside the Quiz screen so the user can speak their answers
/// instead of typing. Tap the orb to dictate the current question's answer; the recognized text
/// streams live into the field via the shared `AppState.quizVoice`. Tap again to stop.
///
/// On-device only — pure speech-to-text. No AI voice, no Claude, no TTS (so there's no robotic
/// read-aloud). A vertical glass pill mirroring `OopsVoiceOrbView`'s shape, minus the replay arrow
/// (nothing to replay): X (close) · amber orb (tap to talk).
struct QuizVoiceOrbView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var stt = SpeechRecognizer()

    /// True only when the user is on a free-text question the orb may write into.
    private var canDictate: Bool { appState.quizVoice.activeQuestionID != nil }

    var body: some View {
        pillContent
            // Stream live partial transcription into the active question's answer. Starting a new
            // dictation resets the transcript to "", which clears the field first (voice replaces
            // any prior text — the user can still edit it by hand afterwards).
            .onChange(of: stt.transcript) { _, text in
                guard let id = appState.quizVoice.activeQuestionID else { return }
                appState.quizVoice.text[id] = text
            }
            // Moving to a non-text question (e.g. the age pills) mid-listen ends dictation cleanly.
            .onChange(of: appState.quizVoice.activeQuestionID) { _, id in
                if id == nil, stt.isListening { stopDictation() }
            }
            .onDisappear { stopDictation() }
    }

    private var pillContent: some View {
        // The window uses `.windowStyle(.plain)` (no system glass), so we draw the Figma "World
        // Bar" capsule ourselves. This yields an exact slim pill at any size, bypassing the
        // shared-space glass-window minimum that otherwise pads a small window into a wide panel.
        VStack(spacing: 0) {
            // .hoverEffect() is required on visionOS so eye tracking recognises the hit target.
            Button { dismissWindow(id: "quiz-voice-orb") } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()

            Spacer()

            Button(action: tap) {
                OrbView(size: 60, isSpeaking: false, isListening: stt.isListening)
                    .opacity(canDictate || stt.isListening ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .disabled(!canDictate && !stt.isListening)

            Spacer()
        }
        .padding(.vertical, 18)
        .frame(width: 110, height: 300)
        .background(pillBackground)
    }

    /// The Figma "World Bar" pill (node 50:1658): glass-blur capsule, faint top-leading →
    /// bottom-trailing gradient, hairline white border, soft drop shadow.
    private var pillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color(white: 0.45, opacity: 0.25)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 1)
    }

    private func tap() {
        if stt.isListening {
            stopDictation()
        } else {
            guard canDictate else { return }
            Task {
                guard await stt.requestAuthorization() else { return }
                do {
                    try activateRecordSession()
                    try stt.start()
                } catch {
                    deactivateSession()
                }
            }
        }
    }

    private func stopDictation() {
        _ = stt.stop()
        deactivateSession()
    }

    // MARK: - Audio session (SpeechRecognizer does not manage one itself)

    private func activateRecordSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .spokenAudio,
                          options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try s.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
#endif
