import Foundation

/// Answers from the five mixed-format quiz questions.
/// energy/minutes have defaults; need/help/week must be chosen by the user.
struct QuizAnswers {
    var energy: Double = 0.45      // Q1 slider: 0 = stillness, 1 = energy
    var need: String? = nil        // Q2 image grid: quiet/connection/movement/creativity
    var help: String? = nil        // Q3 icon grid: alone/talk/move/make
    var week: String? = nil        // Q4 image grid: exam/sleep/home/focus
    var minutes: Int = 10          // Q5 time row

    var isComplete: Bool { need != nil && help != nil && week != nil }
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
