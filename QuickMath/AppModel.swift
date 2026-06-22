import Foundation
import SwiftData
import SwiftUI

/// App state: owns the local SwiftData store, exposes today's puzzle, and derives the streak and
/// lifetime stats from recorded results (never stored as truth).
@MainActor
final class AppModel: ObservableObject {
    let container: ModelContainer
    weak var store: Store?

    @Published private(set) var currentStreak = 0
    @Published private(set) var longestStreak = 0
    @Published private(set) var totalSolved = 0
    @Published private(set) var bestSeconds = 0.0   // fastest solve (lower is better)
    @Published private(set) var solvedToday = false
    @Published private(set) var today: Puzzle?

    init(container: ModelContainer) {
        self.container = container
        today = PuzzleBank.today()
        refresh()
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([LatticeResult.self])
        let local = ModelConfiguration(schema: schema)
        if let c = try? ModelContainer(for: schema, configurations: local) { return c }
        let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: mem)
    }

    func refreshTodayIfNeeded() {
        today = PuzzleBank.today()
        refresh()
    }

    func record(puzzle: Puzzle, solved: Bool, seconds: Double, isExpert: Bool) {
        let ctx = container.mainContext
        ctx.insert(LatticeResult(dateKey: PuzzleBank.dateKey(), puzzleId: puzzle.id,
                                 solved: solved, seconds: seconds, isExpert: isExpert))
        try? ctx.save()
        refresh()
    }

    func allResults() -> [LatticeResult] {
        let d = FetchDescriptor<LatticeResult>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? container.mainContext.fetch(d)) ?? []
    }

    /// The recorded daily result for a date key (ignores expert attempts).
    func result(forKey key: String) -> LatticeResult? {
        allResults().first { $0.dateKey == key && !$0.isExpert && $0.solved }
    }

    func hasSolvedToday() -> Bool { result(forKey: PuzzleBank.dateKey()) != nil }

    func refresh() {
        let solvedDaily = allResults().filter { $0.solved && !$0.isExpert }
        totalSolved = solvedDaily.count
        bestSeconds = solvedDaily.map(\.seconds).filter { $0 > 0 }.min() ?? 0
        solvedToday = solvedDaily.contains { $0.dateKey == PuzzleBank.dateKey() }
        let keys = Set(solvedDaily.map(\.dateKey))
        let s = Self.streaks(from: keys)
        currentStreak = s.current
        longestStreak = s.longest
    }

    /// Current (consecutive days ending today/yesterday) and longest run from solved-day keys.
    static func streaks(from keys: Set<String>) -> (current: Int, longest: Int) {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.timeZone = .current
        let cal = Calendar.current
        let days = Set(keys.compactMap { fmt.date(from: $0) }.map { cal.startOfDay(for: $0) })
        guard !days.isEmpty else { return (0, 0) }

        let sorted = days.sorted()
        var longest = 1, run = 1
        for i in 1..<sorted.count {
            let gap = cal.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            if gap == 1 { run += 1 } else { run = 1 }
            longest = max(longest, run)
        }

        var current = 0
        var cursor = cal.startOfDay(for: .now)
        if !days.contains(cursor) { cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        while days.contains(cursor) {
            current += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return (current, max(longest, current))
    }

    func deleteAllData() {
        let ctx = container.mainContext
        for r in allResults() { ctx.delete(r) }
        try? ctx.save()
        refresh()
    }
}
