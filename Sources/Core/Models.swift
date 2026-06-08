import Foundation

/// One this-or-that slider question (both poles are positive — no bad answer).
/// Left pole = score 0, right pole = score 1.
struct ThisOrThat: Identifiable {
    let id: String
    let question: String
    let leftLabel: String
    let rightLabel: String
}

/// Answers from the 4+1 axis quiz (research direction 3).
struct QuizAnswers {
    /// 12 this-or-that slider values, 0...1 (0 = left pole, 1 = right pole).
    /// Index groups: [0-2] = axis1 autonomy<->belonging, [3-5] = axis2 explore<->stable,
    ///               [6-8] = axis3 expression<->connection, [9-11] = axis4 calm<->vivid.
    var sliders: [Double] = Array(repeating: 0.5, count: 12)
    /// Q14 hope direction — option id string ("ownPath" / "people" / "explore" / "stable").
    var hope: String? = nil
    /// Q15 free text — optional; used for world naming / atmosphere micro-tuning.
    var hopeFreeText: String = ""

    var isComplete: Bool { hope != nil }
}

/// One option of a single-choice question. `image` is the matching world asset name
/// (for image cards); `symbol` is an SF Symbol (for icon cards).
struct ChoiceOption: Identifiable, Hashable {
    let id: String
    let label: String
    var image: String? = nil
    var symbol: String? = nil
}

/// A generated immersive world (pre-baked in v1).
struct World: Identifiable {
    let id: String
    let title: String       // A one-line phrase shown inside the world
    let imageName: String   // v1: name of the 360° image bundled in Assets
    let imageURL: URL?      // v2: remote image returned by the API
    let blurb: String       // Supporting description

    init(id: String, title: String, imageName: String, imageURL: URL? = nil, blurb: String = "") {
        self.id = id
        self.title = title
        self.imageName = imageName
        self.imageURL = imageURL
        self.blurb = blurb
    }
}

// MARK: - Self-alignment scores (research direction 6: the hidden continuous layer)

/// The direction the user wants to grow toward (research axis 5, non-bipolar).
/// Drives the world's distant focal point — never a good/bad score.
enum HopeDirection {
    case ownPath    // More at ease being yourself
    case people     // Closer to other people
    case explore    // Braver about exploring
    case stable     // More grounded and settled
}

/// The hidden bottom layer: where the user sits on each 4+1 axis.
/// Bipolar axes are 0...1 (0 = left pole, 1 = right pole — see comments).
/// Fed to `WorldMapper.map` to produce `WorldParams` (research direction 7).
struct AxisScores {
    var autonomyBelonging: Double    // axis 1  0 = autonomy, 1 = belonging
    var exploreStable: Double        // axis 2  0 = explore, 1 = stable
    var expressionConnection: Double // axis 3  0 = self-expression, 1 = collective connection
    var calmVivid: Double            // axis 4 (state) 0 = calm, 1 = vivid
    var hope: HopeDirection          // axis 5  direction vector

    static let neutral = AxisScores(
        autonomyBelonging: 0.5, exploreStable: 0.5,
        expressionConnection: 0.5, calmVivid: 0.5, hope: .ownPath
    )
}

/// Coarse base world chosen from the structural axes. Research keeps a few
/// authored base structures and varies appearance continuously on top, rather
/// than a fixed preset per personality. Maps to a bundled USDZ.
enum WorldArchetype {
    case openNature     // Open nature       → Free_Low_Poly_Forest
    case cozyCommunal   // Cozy communal     → Cozy_living_room_baked
    case solitaryPath   // Solitary / path   → FREE_Dirt_Road_Through_Forest
    case artGallery     // Art Gallery E 2020 (Oops flow) → bundled USDZ

    /// Archetype USDZ resource name (no extension). NOTE: the three original archetypes
    /// are no longer bundled (test-only; the parametric full-world path degrades when
    /// absent — see `ParametricWorldBuilder.build` returning nil). `artGallery` IS
    /// bundled (SpikeAssets) and used by the Oops flow.
    var usdzName: String {
        switch self {
        case .openNature:   return "Free_Low_Poly_Forest"
        case .cozyCommunal: return "Cozy_living_room_baked"
        case .solitaryPath: return "FREE_Dirt_Road_Through_Forest"
        case .artGallery:   return "Art_Gallery_E_2020"
        }
    }
}

/// The middle layer: concrete, continuously-tunable parameters the display layer
/// applies on top of a base world (research direction 7). Not discrete presets — two
/// users with the same archetype still differ because these values differ.
struct WorldParams {
    var archetype: WorldArchetype   // coarse base (axis 2 / axis 3)
    var lightIntensity: Float       // axis 4 → DirectionalLight intensity
    var colorTemperature: Float     // axis 4 → Kelvin; calm = cooler, vivid = warmer
    var saturation: Double          // axis 4 → 0.5 (desaturated) … 1.1 (saturated)
    var socialDensity: Int          // axis 1 → ambient companions / lanterns to show
    var openness: Double            // axis 2 → 0 (enclosed refuge) … 1 (open prospect)
    var biophilicDensity: Double    // axis 3 → 0.3 (sparse personal) … 1 (lush shared)
    var focal: HopeDirection        // axis 5 → distant focal direction
}
