import SwiftUI

/// Shown after a grid is solved: time, streak, and a Pro share.
struct ResultView: View {
    let puzzle: Puzzle
    let seconds: Int
    let streak: Int
    let isExpert: Bool
    let onDone: () -> Void

    @EnvironmentObject var store: Store

    private var shareText: String {
        "I solved \(isExpert ? "the expert" : "today's") Bridge puzzle in \(timeString(seconds)) — \(streak)-day streak. One bridges puzzle a day."
    }

    var body: some View {
        ZStack {
            QMBackground()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 50, weight: .semibold)).foregroundStyle(Color.qmCorrect)
                Text("Solved!").font(.largeTitle.weight(.heavy))
                Text(isExpert ? "Expert puzzle solved." : "Today's puzzle solved.")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    MetricTile(value: timeString(seconds), label: "Time")
                    MetricTile(value: "\(streak)", label: "Day streak")
                }

                if store.isPro {
                    ShareLink(item: shareText) {
                        Label("Share result", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 2)
                    }
                    .softButton()
                }

                Button { onDone() } label: {
                    Text("Done").frame(maxWidth: .infinity).padding(.vertical, 2)
                }
                .prominentButton()
            }
            .padding(24)
        }
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}
