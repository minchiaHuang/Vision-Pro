import Foundation

/// API keys for the app's cloud services.
///
/// SAFETY: this file is committed and contains **no key literals** — it only resolves
/// keys at runtime from out-of-band sources that are kept out of git. A fresh clone
/// builds with empty keys, and every service guards on `isEmpty` and degrades gracefully.
///
/// Provide a key in either of these places (checked in this order):
///
///   1. An Xcode **scheme environment variable** (best for development).
///      Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Arguments ▸ Environment Variables,
///      add e.g. `OPENAI_API_KEY = sk-…`, and leave "Shared" unchecked so it is stored
///      in your *user* scheme (which git ignores). The key is then never written to a
///      file or embedded in the built binary.
///
///   2. A bundled **`APIKeys.plist`** (a `[String: String]` dictionary). Copy
///      `APIKeys.example.plist` to `APIKeys.plist`, fill in your key, and add the file
///      to the app target. `APIKeys.plist` is gitignored, so it can't be committed.
///      (Template placeholder values starting with `YOUR_` are ignored.)
///
/// NOTE: any key shipped inside a client app can be extracted from the binary. The two
/// options above are fine for a prototype. For a public release, move calls behind a
/// backend proxy so the key lives only on your server and never ships in the app.
enum Secrets {
    /// World Labs API key (experimental 3D/panorama generation).
    static var worldLabsAPIKey: String { value(for: "WORLD_LABS_API_KEY") }

    /// Anthropic API key for the Claude Messages API (voice conversation, storyline text).
    static var anthropicAPIKey: String { value(for: "ANTHROPIC_API_KEY") }

    /// ElevenLabs API key for cloud TTS.
    static var elevenLabsAPIKey: String { value(for: "ELEVEN_LABS_API_KEY") }

    /// Azure Speech API key for cloud TTS (region southeastasia).
    static var azureSpeechKey: String { value(for: "AZURE_SPEECH_KEY") }

    /// OpenAI API key for image generation (`gpt-image-1`) and/or GPT text.
    static var openAIAPIKey: String { value(for: "OPENAI_API_KEY") }

    // MARK: - Resolution

    /// Resolves a key by name: scheme environment variable first, then `APIKeys.plist`.
    /// Returns "" when neither holds a usable value, so callers' `isEmpty` guards keep the
    /// related feature inert on a fresh clone.
    private static func value(for name: String) -> String {
        if let env = ProcessInfo.processInfo.environment[name], isUsable(env) {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let fromPlist = plist[name], isUsable(fromPlist) {
            return fromPlist.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// A value is usable if it's non-blank and not a leftover template placeholder.
    private static func isUsable(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("YOUR_")
    }

    /// Lazily-loaded contents of the optional, gitignored `APIKeys.plist`. Empty if the
    /// file isn't bundled (the default for a fresh clone).
    private static let plist: [String: String] = {
        guard let url = Bundle.main.url(forResource: "APIKeys", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String]
        else { return [:] }
        return dict
    }()
}
