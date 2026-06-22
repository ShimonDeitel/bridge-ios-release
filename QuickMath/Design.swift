import SwiftUI
import UIKit

// MARK: - Minimalist, Apple-native color system
// Flat surfaces, system semantic colors (so Light AND Dark both look right),
// a single Apple-blue accent. No gradients.

extension Color {
    static let qmAccent = Color(hex: "#007AFF")            // the single accent
    static let qmCard = Color(uiColor: .secondarySystemBackground)
    static let qmCard2 = Color(uiColor: .tertiarySystemBackground)
    static let qmField = Color(uiColor: .tertiarySystemFill)
    static let qmHair = Color(uiColor: .separator)
    static let qmCorrect = Color(hex: "#34C759")           // system green for correct feedback
    static let qmWrong = Color(hex: "#FF3B30")             // system red for wrong feedback
}

// MARK: - Flat surfaces (cards / pills / buttons)

extension View {
    func qmCard(cornerRadius: CGFloat = 20) -> some View {
        self.padding(16)
            .background(Color.qmCard, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func qmPill() -> some View {
        self.padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.qmCard, in: Capsule())
    }

    /// Primary action — a clean, flat Apple-blue filled capsule.
    func prominentButton() -> some View { self.buttonStyle(FilledAccentButtonStyle()) }
    /// Secondary action — flat tinted capsule.
    func softButton() -> some View { self.buttonStyle(SoftButtonStyle()) }
}

struct FilledAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .padding(.horizontal, 22)
            .background(Color.qmAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.medium))
            .foregroundStyle(Color.qmAccent)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(Color.qmCard, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Background (flat, adapts to light/dark)

struct QMBackground: View {
    var body: some View { Color(uiColor: .systemBackground).ignoresSafeArea() }
}

// MARK: - Haptics

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
