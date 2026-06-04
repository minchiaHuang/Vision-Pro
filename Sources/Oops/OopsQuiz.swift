import SwiftUI
import AVFAudio

/// 05 · Quiz — a scrollable glass window of 6 reflective questions, a back button that
/// raises the "Are you sure?" dialog, and a Finish CTA. Answers are front-end only.
struct QuizScreen: View {
    @Binding var answers: OopsAnswers
    let onFinish: () -> Void
    let onBack: () -> Void

    @State private var confirm = false
    @State private var dictation = QuizDictation()

    var body: some View {
        ZStack {
            OopsPassthrough(dim: true)

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 44) {
                        ForEach(OopsContent.questions) { q in
                            questionView(q)
                        }
                        HStack {
                            Spacer()
                            Button("Finish", action: onFinish).buttonStyle(OopsButton())
                            Spacer()
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 24)
                    .padding(.bottom, 60)
                }
            }
            .frame(maxWidth: 1180, maxHeight: 820)
            .oopsWindow()
            .padding(.horizontal, 40)
            .padding(.vertical, 50)

            if confirm {
                OopsDialog(
                    title: "Are you sure?",
                    message: "Your progress will be lost forever and you'll need to reenter all your answers if you start over.",
                    confirmTitle: "Yes",
                    onConfirm: { confirm = false; onBack() },
                    onCancel: { confirm = false })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: confirm)
        // Live dictation streams into Q1 while the mic is active.
        .onChange(of: dictation.transcript) { _, newValue in
            if dictation.isListening { answers.q1 = newValue }
        }
        .onDisappear { dictation.stop() }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quiz").oopsTitle(34)
                Text("Take a few minutes to reflect. Your answers will shape the world that's built for you.")
                    .oopsSub(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 80)
            .padding(.trailing, 70)
            .padding(.top, 56)

            Button { confirm = true } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
            .padding(.top, 44)
        }
    }

    @ViewBuilder
    private func questionView(_ q: OopsContent.Question) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(q.label)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(OopsGlass.label1)
                .fixedSize(horizontal: false, vertical: true)

            switch q.kind {
            case .text:
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .trailing) {
                        OopsField(text: bindingFor(q.id), placeholder: q.placeholder, multiline: false)
                        if q.hasMic {
                            Button { Task { await dictation.toggle() } } label: {
                                Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                                    .font(.system(size: 26))
                                    .foregroundStyle(dictation.isListening
                                                     ? Color(red: 1.0, green: 0.36, blue: 0.36)
                                                     : OopsGlass.label2)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 18)
                            .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate answer")
                        }
                    }
                    if q.hasMic {
                        if let err = dictation.error {
                            Text(err)
                                .font(.system(size: 15))
                                .foregroundStyle(.yellow.opacity(0.9))
                        } else if dictation.isListening {
                            Text("Listening… tap the mic to stop")
                                .font(.system(size: 15))
                                .foregroundStyle(OopsGlass.label2)
                        }
                    }
                }
            case .area:
                OopsField(text: bindingFor(q.id), placeholder: q.placeholder, multiline: true)
            case .slider:
                VStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { Double(answers.q2) },
                        set: { answers.q2 = Int($0.rounded()) }), in: 0...10, step: 1)
                    .tint(.white)
                    HStack {
                        Text("0"); Spacer()
                        Text("\(answers.q2)").fontWeight(.medium)
                        Spacer(); Text("10")
                    }
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func bindingFor(_ id: String) -> Binding<String> {
        switch id {
        case "q1": return $answers.q1
        case "q3": return $answers.q3
        case "q4": return $answers.q4
        case "q5": return $answers.q5
        case "q6": return $answers.q6
        default:   return .constant("")
        }
    }
}

// MARK: - Dictation

/// Push-to-talk dictation for the quiz, wrapping the shared `SpeechRecognizer`. Owns a
/// record-capable audio session for the duration of a dictation turn (mirrors
/// `ConversationService.activateRecordSession()`); the live `transcript` is streamed
/// into the bound answer by the view.
@MainActor
@Observable
final class QuizDictation {
    private let stt = SpeechRecognizer()
    var error: String?

    var isListening: Bool { stt.isListening }
    var transcript: String { stt.transcript }

    /// Tap the mic: start dictating, or stop if already listening.
    func toggle() async {
        if stt.isListening { stop(); return }
        error = nil
        guard await stt.requestAuthorization() else {
            error = "Microphone or speech permission is needed to dictate."
            return
        }
        do {
            try activateRecordSession()
            try stt.start()
        } catch {
            self.error = "Could not start the microphone."
        }
    }

    func stop() {
        stt.stop()
        deactivateSession()
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
}
