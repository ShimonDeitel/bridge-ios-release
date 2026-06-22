import XCTest
@testable import QuickMath

/// Unit tests for the pure logic: the deterministic problem generator, answer choices,
/// tier gating, streak math, and the drill tally → result pipeline.
final class QuickMathTests: XCTestCase {

    // Use the built-in fallback templates so tests don't depend on bundle resource loading.
    private func makeGenerator() -> ProblemGenerator {
        ProblemGenerator(wordTemplates: ProblemGenerator.fallbackTemplates)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: Determinism — the same day yields the same drill everywhere (no server).

    func testDailyDrillIsDeterministicForSameDateAndTier() {
        let gen = makeGenerator()
        let day = date(2026, 6, 21)
        let a = gen.dailyDrill(date: day, tier: .medium, perRound: 5)
        let b = gen.dailyDrill(date: day, tier: .medium, perRound: 5)
        XCTAssertEqual(a.count, 3, "a drill has three rounds")
        XCTAssertEqual(a.flatMap { $0 }.map(\.prompt), b.flatMap { $0 }.map(\.prompt),
                       "identical (date, tier) must produce identical prompts")
        XCTAssertEqual(a.flatMap { $0 }.map(\.answer), b.flatMap { $0 }.map(\.answer))
    }

    func testDifferentDaysProduceDifferentDrills() {
        let gen = makeGenerator()
        let one = gen.dailyDrill(date: date(2026, 6, 21), tier: .medium).flatMap { $0 }.map(\.prompt)
        let two = gen.dailyDrill(date: date(2026, 6, 22), tier: .medium).flatMap { $0 }.map(\.prompt)
        XCTAssertNotEqual(one, two, "a different day should generate a different drill")
    }

    func testDrillRoundsAreInOrderTablesMixedWord() {
        let gen = makeGenerator()
        let rounds = gen.dailyDrill(date: date(2026, 6, 21), tier: .easy, perRound: 4)
        XCTAssertTrue(rounds[0].allSatisfy { $0.kind == .tables })
        XCTAssertTrue(rounds[1].allSatisfy { $0.kind == .mixed })
        XCTAssertTrue(rounds[2].allSatisfy { $0.kind == .word })
    }

    // MARK: Problem correctness.

    func testEveryProblemHasFourUniqueChoicesIncludingAnswer() {
        let gen = makeGenerator()
        for tier in Tier.all {
            let problems = gen.dailyDrill(date: date(2026, 6, 21), tier: tier, perRound: 6).flatMap { $0 }
            for p in problems {
                XCTAssertEqual(p.choices.count, 4, "each problem has 4 options")
                XCTAssertEqual(Set(p.choices).count, 4, "options must be unique")
                XCTAssertTrue(p.choices.contains(p.answer), "the correct answer must be an option")
                XCTAssertTrue(p.choices.allSatisfy { $0 >= 0 }, "no negative options")
                XCTAssertTrue(p.isCorrect(p.answer))
            }
        }
    }

    func testTablesAnswersAreActualProducts() {
        let gen = makeGenerator()
        let tables = gen.round(kind: .tables, tier: .easy, count: 20, rng: &fixedRNG)
        for p in tables {
            // Prompt is "a × b" — verify the answer equals the product.
            let parts = p.prompt.split(separator: "×").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(parts.count, 2)
            if let a = Int(parts[0]), let b = Int(parts[1]) {
                XCTAssertEqual(p.answer, a * b, "tables answer must be the product")
            } else {
                XCTFail("could not parse tables prompt: \(p.prompt)")
            }
        }
    }
    private var fixedRNG = SeededRNG(seed: 12345)

    // MARK: Tier gating.

    func testFreeTiersAndProTiers() {
        XCTAssertEqual(Tier.free, [.easy, .medium])
        XCTAssertTrue(Tier.free.allSatisfy { !$0.isPro })
        XCTAssertTrue(Tier.pro.allSatisfy { $0.isPro })
        XCTAssertEqual(Tier.all.count, 4)
    }

    // MARK: Streak math.

    private func days(_ offsets: [Int], cal: Calendar) -> Set<Date> {
        let today = cal.startOfDay(for: Date())
        return Set(offsets.compactMap { cal.date(byAdding: .day, value: -$0, to: today) })
    }

    func testCurrentStreakCountsTodayBackwards() {
        let cal = Calendar.current
        XCTAssertEqual(AppModel.currentStreak(days: days([0, 1, 2], cal: cal), cal: cal), 3)
    }

    func testCurrentStreakHoldsWhenTodayNotYetLogged() {
        let cal = Calendar.current
        XCTAssertEqual(AppModel.currentStreak(days: days([1, 2], cal: cal), cal: cal), 2)
    }

    func testCurrentStreakBreaksWithGap() {
        let cal = Calendar.current
        XCTAssertEqual(AppModel.currentStreak(days: days([0, 2, 3], cal: cal), cal: cal), 1)
        XCTAssertEqual(AppModel.currentStreak(days: [], cal: cal), 0)
    }

    func testLongestStreak() {
        let cal = Calendar.current
        XCTAssertEqual(AppModel.longestStreak(days: days([0, 1, 2, 5, 6], cal: cal), cal: cal), 3)
    }

    // MARK: Drill tally → result.

    func testDrillTallyAggregatesPerOperation() {
        var tally = DrillTally()
        tally.record(op: .multiply, correct: true, elapsed: 1.0)
        tally.record(op: .multiply, correct: false, elapsed: 2.0)
        tally.record(op: .add, correct: true, elapsed: 1.5)
        let result = tally.makeResult(tier: .hard)
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.correct, 2)
        XCTAssertEqual(result.mulCorrect, 1)
        XCTAssertEqual(result.mulTotal, 2)
        XCTAssertEqual(result.addCorrect, 1)
        XCTAssertEqual(result.addTotal, 1)
        XCTAssertEqual(result.tierRaw, "hard")
        XCTAssertEqual(result.seconds, 4.5, accuracy: 0.001)
        XCTAssertEqual(result.accuracy, 2.0 / 3.0, accuracy: 0.001)
    }

    func testResultAccuracyAndPaceWithNoAttempts() {
        let empty = DailyResult()
        XCTAssertEqual(empty.accuracy, 0)
        XCTAssertEqual(empty.secondsPerProblem, 0)
    }

    // MARK: Store.

    @MainActor
    func testStoreProductIDAndPrice() async {
        let store = Store()
        try? await Task.sleep(for: .seconds(0.3))
        XCTAssertEqual(Store.productID, "quickmath_pro_unlock")
        XCTAssertEqual(store.displayPrice, "$0.99")
        XCTAssertFalse(store.isPro, "Pro must start locked")
    }
}
