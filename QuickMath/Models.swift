import Foundation
import SwiftData

// MARK: - Puzzle (Hashiwokakero / "Bridges")

/// One island on the board: grid position (row `r`, col `c`) and its clue `n`
/// (the exact number of bridge-ends that must connect to it).
struct Island: Codable, Equatable {
    let r: Int
    let c: Int
    let n: Int
}

/// A bridge in the *solution*: connects island index `a` to island index `b` with `c` lines (1 or 2).
struct SolutionBridge: Codable, Equatable {
    let a: Int
    let b: Int
    let c: Int
}

/// One Hashiwokakero puzzle on a `w`×`h` grid. The bundled bank guarantees each puzzle has a
/// single solution; the app is a pure player.
struct Puzzle: Codable, Identifiable, Equatable {
    let id: Int
    let w: Int
    let h: Int
    let difficulty: String
    let islands: [Island]
    let solution: [SolutionBridge]
}

/// An unordered pair of island indices (a < b), used to key bridge counts.
struct PairKey: Hashable {
    let a: Int
    let b: Int
    init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
}

/// The bundled puzzle bank. Free daily puzzles are easy/medium; the Pro "expert" grid is hard.
/// The puzzle for a day is chosen deterministically from the date, so everyone gets the same one.
enum PuzzleBank {
    static let all: [Puzzle] = load()

    static var daily: [Puzzle] {
        let d = all.filter { $0.difficulty == "easy" || $0.difficulty == "medium" }
        return d.isEmpty ? all : d
    }

    static var expert: [Puzzle] {
        let h = all.filter { $0.difficulty == "hard" }
        return h.isEmpty ? all.filter { $0.difficulty == "medium" } : h
    }

    private static func load() -> [Puzzle] {
        guard let url = Bundle.main.url(forResource: "bridge_puzzles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let puzzles = try? JSONDecoder().decode([Puzzle].self, from: data) else { return [] }
        return puzzles
    }

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

// MARK: - Play state

/// A connectable island pair plus its orientation, derived once per puzzle.
struct Link: Identifiable {
    let a: Int
    let b: Int
    let horizontal: Bool
    var id: String { "\(a)-\(b)" }
    var key: PairKey { PairKey(a, b) }
}

/// Mutable state for one play session: how many bridges (0/1/2) sit on each connectable pair,
/// with crossing-prevention and solve detection.
final class BridgeState: ObservableObject {
    let puzzle: Puzzle
    let links: [Link]
    private let solutionMap: [PairKey: Int]

    @Published var counts: [PairKey: Int] = [:]

    init(_ p: Puzzle) {
        puzzle = p
        links = Self.computeLinks(p)
        var sol: [PairKey: Int] = [:]
        for s in p.solution { sol[PairKey(s.a, s.b)] = s.c }
        solutionMap = sol
    }

    /// Connectable pairs: islands aligned in a row or column with no island between them. The
    /// solution's pairs are unioned in defensively so every required bridge is always placeable.
    static func computeLinks(_ p: Puzzle) -> [Link] {
        let isl = p.islands
        let n = isl.count
        var found: [PairKey: Bool] = [:]   // key -> horizontal

        for i in 0..<n {
            for j in (i + 1)..<n {
                if isl[i].r == isl[j].r {
                    let lo = min(isl[i].c, isl[j].c), hi = max(isl[i].c, isl[j].c)
                    let blocked = isl.contains { $0.r == isl[i].r && $0.c > lo && $0.c < hi }
                    if !blocked { found[PairKey(i, j)] = true }
                } else if isl[i].c == isl[j].c {
                    let lo = min(isl[i].r, isl[j].r), hi = max(isl[i].r, isl[j].r)
                    let blocked = isl.contains { $0.c == isl[i].c && $0.r > lo && $0.r < hi }
                    if !blocked { found[PairKey(i, j)] = false }
                }
            }
        }
        // Defensive union with solution pairs.
        for s in p.solution {
            let k = PairKey(s.a, s.b)
            if found[k] == nil { found[k] = isl[s.a].r == isl[s.b].r }
        }
        return found.map { Link(a: $0.key.a, b: $0.key.b, horizontal: $0.value) }
            .sorted { $0.id < $1.id }
    }

    private func link(for key: PairKey) -> Link? { links.first { $0.key == key } }

    /// Total bridge-ends currently connected to an island.
    func degree(_ island: Int) -> Int {
        counts.reduce(0) { acc, kv in
            (kv.key.a == island || kv.key.b == island) ? acc + kv.value : acc
        }
    }

    func remaining(_ island: Int) -> Int { puzzle.islands[island].n - degree(island) }

    /// Tap a link: cycle 0 → 1 → 2 → 0. Adding the first bridge is blocked if it would cross an
    /// existing perpendicular bridge (standard Hashi rule).
    func cycle(_ key: PairKey) {
        let cur = counts[key] ?? 0
        if cur == 0 {
            guard let l = link(for: key), !wouldCross(l) else {
                Haptics.warning(); return
            }
        }
        counts[key] = (cur + 1) % 3
        objectWillChange.send()
    }

    /// Does placing link `l` cross any existing perpendicular bridge?
    private func wouldCross(_ l: Link) -> Bool {
        let isl = puzzle.islands
        let A = isl[l.a], B = isl[l.b]
        for other in links where (counts[other.key] ?? 0) > 0 {
            if other.horizontal == l.horizontal { continue }
            let oa = isl[other.a], ob = isl[other.b]
            if l.horizontal {
                // l: row A.r, cols [minC, maxC]; other: col oa.c, rows [minR, maxR]
                let r = A.r
                let cLo = min(A.c, B.c), cHi = max(A.c, B.c)
                let col = oa.c
                let rLo = min(oa.r, ob.r), rHi = max(oa.r, ob.r)
                if col > cLo && col < cHi && r > rLo && r < rHi { return true }
            } else {
                let col = A.c
                let rLo = min(A.r, B.r), rHi = max(A.r, B.r)
                let r = oa.r
                let cLo = min(oa.c, ob.c), cHi = max(oa.c, ob.c)
                if r > rLo && r < rHi && col > cLo && col < cHi { return true }
            }
        }
        return false
    }

    func clear() { counts = [:]; objectWillChange.send() }

    var placedIslands: Int {
        (0..<puzzle.islands.count).filter { remaining($0) == 0 && puzzle.islands[$0].n > 0 }.count
    }

    /// Solved exactly when the placed bridges equal the unique solution.
    var isSolved: Bool {
        let placed = counts.filter { $0.value > 0 }
        if placed.count != solutionMap.count { return false }
        for (k, v) in placed where solutionMap[k] != v { return false }
        return true
    }
}

/// One recorded attempt at a daily (or expert) puzzle. Local-only; defaults + no unique
/// constraints keep it CloudKit-compatible if sync is ever added.
@Model
final class BridgeResult {
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
