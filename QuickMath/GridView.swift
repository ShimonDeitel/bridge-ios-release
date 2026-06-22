import SwiftUI

/// The player: tap between two islands to add a bridge (tap again for a double bridge, again to
/// clear). Match every island's clue, keep all islands connected, and don't cross bridges.
struct BoardView: View {
    let puzzle: Puzzle
    var isExpert: Bool = false

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @StateObject private var board: BridgeState
    @State private var elapsed = 0
    @State private var solved = false
    @State private var showResult = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(puzzle: Puzzle, isExpert: Bool = false) {
        self.puzzle = puzzle
        self.isExpert = isExpert
        _board = StateObject(wrappedValue: BridgeState(puzzle))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                QMBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        statusBar
                        boardCard
                        legend
                        controls
                    }
                    .padding()
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(isExpert ? "Expert Puzzle" : "Today's Puzzle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }.tint(Color.qmAccent)
                }
            }
            .onReceive(timer) { _ in if !solved { elapsed += 1 } }
            .sheet(isPresented: $showResult) {
                ResultView(puzzle: puzzle, seconds: elapsed, streak: appModel.currentStreak, isExpert: isExpert) {
                    showResult = false; dismiss()
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Label(timeString(elapsed), systemImage: "clock")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Text("\(board.placedIslands)/\(puzzle.islands.count) islands")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var boardCard: some View {
        GeometryReader { geo in
            let cell = geo.size.width / CGFloat(puzzle.w)
            ZStack(alignment: .topLeading) {
                bridgeCanvas(cell: cell)
                ForEach(board.links) { link in
                    Color.clear
                        .frame(width: cell * 0.66, height: cell * 0.66)
                        .contentShape(Circle())
                        .position(midpoint(link, cell))
                        .onTapGesture {
                            guard !solved else { return }
                            Haptics.soft(); board.cycle(link.key); evaluate()
                        }
                }
                ForEach(Array(puzzle.islands.enumerated()), id: \.offset) { i, _ in
                    islandView(i, cell: cell)
                        .position(center(i, cell))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: cell * CGFloat(puzzle.h), alignment: .topLeading)
        }
        .aspectRatio(CGFloat(puzzle.w) / CGFloat(puzzle.h), contentMode: .fit)
        .padding(8)
        .qmCard(cornerRadius: 18)
    }

    private func bridgeCanvas(cell: CGFloat) -> some View {
        Canvas { ctx, _ in
            for link in board.links {
                let cnt = board.counts[link.key] ?? 0
                guard cnt > 0 else { continue }
                let pa = center(link.a, cell)
                let pb = center(link.b, cell)
                let off: CGFloat = max(2.5, cell * 0.09)
                let (dx, dy): (CGFloat, CGFloat) = link.horizontal ? (0, off) : (off, 0)
                let lines: [CGFloat] = cnt == 2 ? [-1, 1] : [0]
                for s in lines {
                    var p = Path()
                    p.move(to: CGPoint(x: pa.x + dx * s, y: pa.y + dy * s))
                    p.addLine(to: CGPoint(x: pb.x + dx * s, y: pb.y + dy * s))
                    ctx.stroke(p, with: .color(Color.qmAccent), lineWidth: max(2.5, cell * 0.07))
                }
            }
        }
    }

    private func islandView(_ i: Int, cell: CGFloat) -> some View {
        let remaining = board.remaining(i)
        let stroke: Color = remaining == 0 ? Color.qmCorrect : (remaining < 0 ? Color.qmWrong : Color.qmHair)
        let d = cell * 0.78
        return ZStack {
            Circle().fill(Color(uiColor: .systemBackground))
            Circle().strokeBorder(stroke, lineWidth: remaining == 0 ? 3 : 1.5)
            Text("\(puzzle.islands[i].n)")
                .font(.system(size: d * 0.5, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.5)
        }
        .frame(width: d, height: d)
    }

    private var legend: some View {
        Text("Tap between two islands to lay a bridge. Tap again for a double, once more to clear. Match every island's number, connect them all, and don't cross bridges.")
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .qmCard()
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            if store.isPro {
                Button { Haptics.tap(); revealHint() } label: {
                    Label("Reveal a bridge", systemImage: "lightbulb.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 2)
                }
                .softButton().disabled(solved)
            }
            Button(role: .destructive) { Haptics.tap(); board.clear() } label: {
                Label("Clear board", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity).padding(.vertical, 2)
            }
            .softButton().disabled(solved)
        }
    }

    /// Pro hint: place one correct bridge the player is still missing.
    private func revealHint() {
        for s in puzzle.solution {
            let key = PairKey(s.a, s.b)
            if (board.counts[key] ?? 0) != s.c {
                board.counts[key] = s.c
                board.objectWillChange.send()
                evaluate()
                return
            }
        }
    }

    private func evaluate() {
        guard !solved else { return }
        if board.isSolved {
            solved = true
            Haptics.success()
            appModel.record(puzzle: puzzle, solved: true, seconds: Double(elapsed), isExpert: isExpert)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showResult = true }
        }
    }

    private func center(_ i: Int, _ cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(puzzle.islands[i].c) + 0.5) * cell,
                y: (CGFloat(puzzle.islands[i].r) + 0.5) * cell)
    }

    private func midpoint(_ link: Link, _ cell: CGFloat) -> CGPoint {
        let pa = center(link.a, cell), pb = center(link.b, cell)
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}
