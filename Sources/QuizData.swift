import Foundation

/// Research 4+1 axis quiz data (研究方向 3: PVQ portrait / this-or-that / hope direction).
/// Questions use autonomy-supportive language (研究方向 4): no "should/must", both poles positive.
enum QuizData {

    // MARK: - Axis 1: 自主 ↔ 歸屬 (Q1–Q3)

    static let axis1: [ThisOrThat] = [
        ThisOrThat(
            id: "q1",
            question: "A just-right weekend for you would be—",
            leftLabel: "on my own, at my own pace",
            rightLabel: "with people I care about"
        ),
        ThisOrThat(
            id: "q2",
            question: "Making a big decision, what matters most—",
            leftLabel: "I chose this myself",
            rightLabel: "we decided together"
        ),
        ThisOrThat(
            id: "q3",
            question: "At the end of a good day, you'd want—",
            leftLabel: "time that's fully yours",
            rightLabel: "to know someone is near"
        ),
    ]

    // MARK: - Axis 2: 探索 ↔ 穩定 (Q4–Q6)

    static let axis2: [ThisOrThat] = [
        ThisOrThat(
            id: "q4",
            question: "Thinking about the year ahead, you lean toward—",
            leftLabel: "trying something new",
            rightLabel: "deepening what matters now"
        ),
        ThisOrThat(
            id: "q5",
            question: "Facing an unfamiliar path, you'd rather—",
            leftLabel: "walk forward and see",
            rightLabel: "make sure the ground is solid"
        ),
        ThisOrThat(
            id: "q6",
            question: "The rhythm you want your life to have—",
            leftLabel: "variety and surprise",
            rightLabel: "steady and predictable"
        ),
    ]

    // MARK: - Axis 3: 自我表達 ↔ 集體連結 (Q7–Q9)

    static let axis3: [ThisOrThat] = [
        ThisOrThat(
            id: "q7",
            question: "When you do something you're proud of, you want it to—",
            leftLabel: "show something uniquely you",
            rightLabel: "genuinely help someone"
        ),
        ThisOrThat(
            id: "q8",
            question: "In a group, you'd rather be—",
            leftLabel: "the voice with a clear style",
            rightLabel: "the one who holds everyone together"
        ),
        ThisOrThat(
            id: "q9",
            question: "Your ideal kind of accomplishment is—",
            leftLabel: "something you made and signed",
            rightLabel: "something you were part of that helped"
        ),
    ]

    // MARK: - Axis 4: 平靜 ↔ 生機 (Q10–Q12, state axis)

    static let axis4: [ThisOrThat] = [
        ThisOrThat(
            id: "q10",
            question: "Lately, what you find yourself reaching for—",
            leftLabel: "to slow down and be held",
            rightLabel: "to move and feel lit up"
        ),
        ThisOrThat(
            id: "q11",
            question: "A space you could step into right now—",
            leftLabel: "quiet and soft, let you settle",
            rightLabel: "bright and alive, pull you forward"
        ),
        ThisOrThat(
            id: "q12",
            question: "What you need right now—",
            leftLabel: "to restore and settle",
            rightLabel: "to feel alive and move"
        ),
    ]

    /// All four axis groups in step order (step 0 → axis1, step 3 → axis4).
    static let axisGroups: [[ThisOrThat]] = [axis1, axis2, axis3, axis4]

    /// Soft situational titles for each axis screen (not abstract axis names).
    static let axisTitles: [String] = [
        "How do you want to spend your time?",
        "What does change feel like to you?",
        "Where does your energy tend to go?",
        "What are you reaching for right now?",
    ]

    // MARK: - Q14: Hope direction (軸5, non-bipolar)

    /// Four directions mapped 1-to-1 to `HopeDirection` cases in `Scorer`.
    static let hopeOptions: [ChoiceOption] = [
        ChoiceOption(id: "ownPath", label: "More at ease\nbeing myself",  symbol: "person.crop.circle"),
        ChoiceOption(id: "people",  label: "Closer to\nothers",           symbol: "person.2.fill"),
        ChoiceOption(id: "explore", label: "Braver to\nexplore",          symbol: "arrow.forward.circle"),
        ChoiceOption(id: "stable",  label: "More grounded\nand steady",   symbol: "house.fill"),
    ]

    /// Total number of quiz steps: 4 axis screens + hope direction + free text.
    static let stepCount = 6
}
