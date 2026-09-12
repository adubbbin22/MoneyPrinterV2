import Foundation

/// Per-frame colour statistics extracted from the camera ROI.
public struct FrameSample: Equatable {
    public let timestamp: Double
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(timestamp: Double, red: Double, green: Double, blue: Double) {
        self.timestamp = timestamp
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Why a frame was rejected, phrased as the corrective action to show the user.
public enum ContactIssue: Equatable {
    case noFinger
    case tooLight
    case saturated
    case moving

    public var guidance: String {
        switch self {
        case .noFinger:  return "Cover the camera and flash with your fingertip"
        case .tooLight:  return "Press a little more firmly to block outside light"
        case .saturated: return "Ease off — you're pressing too hard"
        case .moving:    return "Hold still"
        }
    }
}

/// Continuous gate on whether a usable fingertip signal is present.
///
/// This exists so the app never produces a number from a bad signal. A camera
/// pointed at a ceiling still yields a periodic-looking trace once filtered,
/// and without this gate the estimator would happily report a heart rate for it.
public struct ContactMonitor {
    /// Below this the frame is not a torch-lit fingertip.
    public static let minimumRed: Double = 0.60
    /// Above this the sensor is clipping and the pulse is crushed out.
    public static let saturationCeiling: Double = 0.995
    /// A fingertip passes red far better than green or blue; a high ratio of
    /// either means ambient light is leaking past the finger.
    public static let maximumOtherChannelRatio: Double = 0.80
    /// Frame-to-frame red jump above which the finger is considered to be moving.
    /// The pulsatile component is well under 1% of DC, so anything this large
    /// is motion, not physiology.
    public static let motionThreshold: Double = 0.05

    private var previousRed: Double?

    public init() {}

    /// Evaluate one frame. Returns nil when the frame is usable.
    public mutating func evaluate(_ sample: FrameSample) -> ContactIssue? {
        defer { previousRed = sample.red }

        if sample.red < Self.minimumRed { return .noFinger }
        if sample.red > Self.saturationCeiling { return .saturated }

        let others = max(sample.green, sample.blue)
        if sample.red > 0, others / sample.red > Self.maximumOtherChannelRatio {
            return .tooLight
        }
        if let previous = previousRed, abs(sample.red - previous) > Self.motionThreshold {
            return .moving
        }
        return nil
    }

    public mutating func reset() { previousRed = nil }
}
