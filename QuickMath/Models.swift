import Foundation
import SwiftData

/// One logic-grid puzzle: people (rows) matched one-to-one to an ordered attribute (cols),
/// pinned down by a set of clues. `solution[r]` is the column index for row r.
struct Puzzle: Codable, Identifiable, Equatable {
    let id: Int
    let size: Int
    let rowCategory: String
    let colCategory: String
    let rows: [String]
    let cols: [String]
    let solution: [Int]
    let clues: [String]
}

/// The bundled puzzle bank. Daily puzzles are size 5; expert (Pro) are size 6. The puzzle for a
/// given day is chosen deterministically from the date, so everyone gets the same one.
enum PuzzleBank {
    private struct Bank: Codable { let version: Int; let puzzles: [Puzzle] }

    static let all: [Puzzle] = load()
    static var daily: [Puzzle] { all.filter { $0.size == 5 } }
    static var expert: [Puzzle] { all.filter { $0.size == 6 } }

    private static func load() -> [Puzzle] {
        guard let url = Bundle.main.url(forResource: "lattice_puzzles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bank = try? JSONDecoder().decode(Bank.self, from: data) else { return [] }
        return bank.puzzles
    }

    /// Days since the epoch, used as a stable per-day index.
    private static func epochDay(_ date: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        return Int((start.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    static func index(for date: Date, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let d = epochDay(date)
        return ((d % count) + count) % count
    }

    static func today(for date: Date = .now) -> Puzzle? {
        let d = daily; guard !d.isEmpty else { return nil }
        return d[index(for: date, count: d.count)]
    }

    static func expertToday(for date: Date = .now) -> Puzzle? {
        let e = expert; guard !e.isEmpty else { return nil }
        return e[index(for: date, count: e.count)]
    }

    /// The daily puzzle for a day N days back (Pro archive).
    static func daily(daysAgo: Int, from date: Date = .now) -> Puzzle? {
        let d = daily; guard !d.isEmpty else { return nil }
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: date) ?? date
        return d[index(for: day, count: d.count)]
    }

    static func dateKey(for date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
}

/// A single cell's mark in the grid.
enum Mark: Int { case blank = 0, yes, no }

/// Mutable state for one play session: an n×n grid of marks plus solve detection.
final class GridState: ObservableObject {
    let puzzle: Puzzle
    @Published var marks: [[Mark]]
    @Published var hintedRow: Int? = nil

    init(_ p: Puzzle) {
        puzzle = p
        marks = Array(repeating: Array(repeating: .blank, count: p.size), count: p.size)
    }

    /// Tap cycles blank → yes → no → blank. Placing a YES auto-marks the rest of that row and
    /// column NO (one-to-one matching), the way players naturally fill a logic grid.
    func cycle(_ r: Int, _ c: Int) {
        let n = puzzle.size
        let next: Mark = marks[r][c] == .blank ? .yes : (marks[r][c] == .yes ? .no : .blank)
        marks[r][c] = next
        if next == .yes {
            for cc in 0..<n where cc != c && marks[r][cc] != .no { marks[r][cc] = .no }
            for rr in 0..<n where rr != r && marks[rr][c] != .no { marks[rr][c] = .no }
        }
        objectWillChange.send()
    }

    /// Reveal one correct cell the player hasn't placed yet (Pro hint).
    func revealHint() {
        let n = puzzle.size
        for r in 0..<n where marks[r][puzzle.solution[r]] != .yes {
            for c in 0..<n { marks[r][c] = (c == puzzle.solution[r]) ? .yes : .no }
            hintedRow = r
            objectWillChange.send()
            return
        }
    }

    var placedCount: Int {
        (0..<puzzle.size).reduce(0) { acc, r in
            acc + ((0..<puzzle.size).contains { marks[r][$0] == .yes } ? 1 : 0)
        }
    }

    var isComplete: Bool { placedCount == puzzle.size }

    var isSolved: Bool {
        for r in 0..<puzzle.size {
            let yes = (0..<puzzle.size).filter { marks[r][$0] == .yes }
            if yes.count != 1 || yes[0] != puzzle.solution[r] { return false }
        }
        return true
    }
}

/// One recorded attempt at a daily (or expert) grid. Local-only; defaults + no unique constraints
/// keep it CloudKit-compatible if sync is ever added.
@Model
final class LatticeResult {
    var id: UUID = UUID()
    var dateKey: String = ""
    var puzzleId: Int = 0
    var solved: Bool = false
    var seconds: Double = 0
    var isExpert: Bool = false
    var date: Date = Date.now

    init(id: UUID = UUID(), dateKey: String = "", puzzleId: Int = 0,
         solved: Bool = false, seconds: Double = 0, isExpert: Bool = false, date: Date = .now) {
        self.id = id; self.dateKey = dateKey; self.puzzleId = puzzleId
        self.solved = solved; self.seconds = seconds; self.isExpert = isExpert; self.date = date
    }
}
