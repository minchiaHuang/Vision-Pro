import SwiftUI

/// The Future Museum entry form (typed-first — no voice in this milestone). Six inputs
/// mapped to the Hero's-Journey "cost points"; only the role (the Call) is required, the
/// rest are optional and inferred by the Curator when left blank.
struct MuseumQuestionsView: View {
    @Binding var answers: MuseumAnswers
    let onGenerate: () -> Void

    private var canGenerate: Bool {
        !answers.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(white: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    field("Who do you want to become?",
                          text: $answers.role,
                          placeholder: "a professional ballet dancer",
                          required: true)

                    HStack(alignment: .bottom, spacing: 20) {
                        agePicker
                        field("Where do you live?",
                              text: $answers.city, placeholder: "Sydney")
                    }

                    field("What's been stopping you?",
                          text: $answers.fear, placeholder: "I started too late")

                    field("What are you least willing to give up for it?",
                          text: $answers.sacrifice, placeholder: "time with my family")

                    field("What would make it worth it — even if you never make it?",
                          text: $answers.worthIt, placeholder: "one moment on a real stage")

                    generateButton
                        .padding(.top, 8)
                }
                .padding(40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FUTURE MUSEUM")
                .font(.system(size: 13, weight: .semibold)).tracking(2)
                .foregroundStyle(.orange.opacity(0.8))
            Text("Walk the path you're considering — including the parts no one tells you about.")
                .font(.system(size: 26, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private func field(_ label: String, text: Binding<String>,
                       placeholder: String, required: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 17, weight: .medium))
                if required {
                    Text("required").font(.system(size: 12))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(14)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private var agePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How old are you?").font(.system(size: 17, weight: .medium))
            Stepper(value: $answers.age, in: 14...70) {
                Text("\(answers.age)").font(.system(size: 18, weight: .medium))
                    .frame(minWidth: 44, alignment: .leading)
            }
            .padding(10)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .frame(width: 200)
        }
    }

    private var generateButton: some View {
        Button(action: onGenerate) {
            Text("Build my museum")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!canGenerate)
        .opacity(canGenerate ? 1 : 0.5)
    }
}
