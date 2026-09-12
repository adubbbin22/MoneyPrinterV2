import SwiftUI
import PulseLogCore

/// Design tokens.
///
/// Deliberately restrained. Health data reads as more credible in a calm
/// interface than in a saturated one, and the category colours have to carry
/// meaning, so they are the only strong colours in the app.
enum Theme {
    static let accent = Color(red: 0.85, green: 0.22, blue: 0.31)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let pageBackground = Color(.systemGroupedBackground)

    static let cornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16

    /// Colours for blood-pressure categories.
    ///
    /// These run green through red in a single ramp so severity is legible at
    /// a glance, and each is paired with a text label everywhere it appears —
    /// colour alone would exclude anyone with a colour vision deficiency.
    static func color(for category: BloodPressureCategory) -> Color {
        switch category {
        case .low:      return Color(red: 0.25, green: 0.52, blue: 0.78)
        case .normal:   return Color(red: 0.18, green: 0.60, blue: 0.38)
        case .elevated: return Color(red: 0.85, green: 0.65, blue: 0.13)
        case .stage1:   return Color(red: 0.88, green: 0.46, blue: 0.16)
        case .stage2:   return Color(red: 0.82, green: 0.25, blue: 0.20)
        case .crisis:   return Color(red: 0.62, green: 0.11, blue: 0.13)
        }
    }

    static func color(for band: HeartRateNorms.Band) -> Color {
        switch band {
        case .low:      return Color(red: 0.25, green: 0.52, blue: 0.78)
        case .normal:   return Color(red: 0.18, green: 0.60, blue: 0.38)
        case .elevated: return Color(red: 0.85, green: 0.65, blue: 0.13)
        case .high:     return Color(red: 0.82, green: 0.25, blue: 0.20)
        }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}
