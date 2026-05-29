import Foundation

/// API key stubs for experimental services.
///
/// This file IS committed to the repo with empty placeholder values so that
/// every clean clone builds out of the box. Do NOT replace these placeholders
/// with real keys in a commit.
///
/// For local development with real keys, either:
///   1. Override the values locally and keep the change unstaged
///      (`git update-index --skip-worktree Sources/Secrets.swift` if you
///      want extra protection against accidental commits), or
///   2. Move secrets to an out-of-band file (e.g. `APIKeys.plist`, env vars)
///      and read them at runtime instead of hard-coding here.
///
/// Note: the WorldLabs entry point ("Experimental: World Labs" on the splash)
/// is a spike and is not part of the main v2 product flow. With the empty
/// key below, `WorldLabsService` reports "Missing API key" and stays inert —
/// this is the expected behavior for a fresh clone.
enum Secrets {
    /// World Labs API key. Empty by default; replace locally only.
    static let worldLabsAPIKey: String = ""
}
