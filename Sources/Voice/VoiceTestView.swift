import SwiftUI

// ⚠️ DEV / VERIFICATION ONLY — do NOT ship.
// Standalone entry for the AI voice companion, reached from the Dev Menu. In the real
// app the voice feature lives inside the world (WorldView); this screen drives the same
// `VoiceMascot` / `ConversationService` in isolation so it can be tested without the
// quiz/world.
struct VoiceTestView: View {
    /// A neutral preset so the guide has a world/persona to ground its replies.
    private let world = WorldCatalog.world(for: .cozyCommunal)
    private let scores = AxisScores.neutral

    var body: some View {
        ZStack {
            WarmBackground()

            VStack(spacing: 28) {
                Eyebrow("Voice Companion — test")

                VoiceMascot(
                    size: 140,
                    configure: { convo in
                        convo.configure(world: world, scores: scores,
                                        params: WorldMapper.map(scores), hopeFreeText: "")
                    },
                    welcome: { "Hi — I'm your guide. Tap the orb and say something to test the voice." }
                )

                Text("Tap the orb to talk · long-press to replay the welcome")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
    }
}
