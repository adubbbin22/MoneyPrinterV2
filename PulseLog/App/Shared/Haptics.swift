import CoreHaptics
import UIKit

/// A tap on each detected beat.
///
/// This is the strongest perceived-accuracy cue in the whole measurement: a
/// pulse you can feel in time with your own reads as real in a way a number
/// alone does not. It is also the one place where faking it would be
/// dishonest, so the tick is driven by detected beats, never by a timer.
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .soft)
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() { impact.prepare() }

    static func beat() { impact.impactOccurred(intensity: 0.7) }

    static func success() { notification.notificationOccurred(.success) }

    static func warning() { notification.notificationOccurred(.warning) }
}
