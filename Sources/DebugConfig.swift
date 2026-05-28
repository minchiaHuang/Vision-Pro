import Foundation

// ============================================================================
//  ⚠️  DEV-ONLY SHORTCUTS — do NOT ship with non-default values.
//
//  When `skipQuizTo` is non-nil, the splash + 5-question quiz are bypassed
//  on launch and the app lands directly in the World view. Useful while we
//  iterate on the 6DoF spike without sitting through the quiz every run.
//
//  Before any demo, commit, or AFP submission build:
//
//      skipQuizTo  = nil
//      autoOpenSpike = false
//
//  See plan file → "Addendum — Dev Shortcut" for the full rationale.
// ============================================================================

enum DebugConfig {

    /// Skip splash + quiz + loading and land directly in the World view.
    ///
    /// - `nil` ........... normal flow (Splash → Quiz → Loading → World)
    /// - World.id string  app launches in `.world` phase with that world
    ///                    resolved. Valid IDs (from `WorldCatalog.all`):
    ///                    `"starry_night"`, `"open_nature"`,
    ///                    `"warm_communal"`, `"quiet_solitary"`.
    ///
    /// The chosen world's `imageName` / `sceneName` still drives whichever
    /// rendering path the user enters — missing assets fall back to the
    /// gray sphere / placeholder cube as in the normal flow.
    static let skipQuizTo: String? = "warm_communal"

    /// Auto-enter the 6DoF spike view as soon as the World screen appears.
    ///
    /// Only meaningful when `skipQuizTo` is also set. On iOS this auto-
    /// presents the `Scene3DView` full-screen cover; on visionOS it auto-
    /// opens the `world_3d` ImmersiveSpace.
    ///
    /// Set to `false` to land on the World screen and let the user decide
    /// whether to enter 3DoF skybox or 6DoF.
    static let autoOpenSpike: Bool = false
}
