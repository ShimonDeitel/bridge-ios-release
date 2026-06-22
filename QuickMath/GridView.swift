import SwiftUI

/// The player: a one-to-one matching grid (people × an ordered attribute). Read the clues, tap
/// cells to mark ✓ / ✗, and solve. Placing a ✓ auto-crosses the rest of its row and column.
struct GridView: View {
    let puzzle: Puzzle
    var isExpert: Bool = false

    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @StateObject private var grid: GridState
    @State private var elapsed = 0
    @State private var solved = false
    @State private var wrongShake = false
    @State private var showResult = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(puzzle: Puzzle, isExpert: Bool = false) {
        self.puzzle = puzzle
        self.isExpert = isExpert
        _grid = StateObject(wrappedValue: GridState(puzzle))
    }

    private var cell: CGFloat { puzzle.size >= 6 ? 38 : 44 }
    private let nameW: CGFloat = 74

    var body: some View {
        NavigationStack {
            ZStack {
                QMBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        timerBar
                        gridBlock
                            .modifier(Shake(animatableData: wrongShake ? 1 : 0))
                        cluesCard
                        if store.isPro {
                            Button { Haptics.tap(); grid.revealHint(); evaluate() } label: {
                                Label("Reveal a hint", systemImage: "lightbulb.fill")
                                    .frame(maxWidth: .infinity).padding(.vertical, 2)
                            }
                            .softButton().disabled(solved)
                        }
                    }
                    .padding()
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(isExpert ? "Expert Grid" : "Today's Grid")
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

    private var timerBar: some View {
        HStack {
            Label(timeString(elapsed), systemImage: "clock").font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(grid.placedCount)/\(puzzle.size) placed").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var gridBlock: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text(puzzle.colCategory).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: nameW, height: 46, alignment: .trailing)
                    .padding(.trailing, 4)
                ForEach(0..<puzzle.size, id: \.self) { c in
                    Text(puzzle.cols[c]).font(.system(size: 10, weight: .semibold))
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                        .frame(width: cell, height: 46)
                }
            }
            ForEach(0..<puzzle.size, id: \.self) { r in
                HStack(spacing: 0) {
                    Text(puzzle.rows[r]).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: nameW, height: cell, alignment: .trailing).padding(.trailing, 4)
                    ForEach(0..<puzzle.size, id: \.self) { c in
                        cellView(r, c)
                    }
                }
            }
        }
        .qmCard(cornerRadius: 16)
    }

    private func cellView(_ r: Int, _ c: Int) -> some View {
        Button {
            guard !solved else { return }
            Haptics.soft(); grid.cycle(r, c); evaluate()
        } label: {
            ZStack {
                Rectangle().fill(Color.qmCard2)
                switch grid.marks[r][c] {
                case .yes: Image(systemName: "checkmark").font(.system(size: cell * 0.42, weight: .bold)).foregroundStyle(Color.qmAccent)
                case .no:  Image(systemName: "xmark").font(.system(size: cell * 0.34, weight: .semibold)).foregroundStyle(Color.secondary)
                case .blank: Color.clear
                }
            }
            .frame(width: cell, height: cell)
            .overlay(Rectangle().stroke(Color.qmHair, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var cluesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLUES").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1.5)
            ForEach(Array(puzzle.clues.enumerated()), id: \.offset) { i, clue in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).").font(.subheadline.weight(.semibold)).foregroundStyle(Color.qmAccent)
                    Text(clue).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .qmCard()
    }

    private func evaluate() {
        guard !solved else { return }
        if grid.isSolved {
            solved = true
            Haptics.success()
            appModel.record(puzzle: puzzle, solved: true, seconds: Double(elapsed), isExpert: isExpert)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showResult = true }
        } else if grid.isComplete {
            Haptics.warning()
            withAnimation(.default) { wrongShake.toggle() }
        }
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

/// A small horizontal shake for a completed-but-wrong grid.
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
