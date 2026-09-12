import Foundation

/// Drives one heart-rate measurement from a stream of camera frames.
///
/// Deliberately free of AVFoundation and SwiftUI: contact gating, the paused
/// countdown and the retake decision are the parts most likely to contain
/// bugs, so they live where they can be tested without a device.
public final class MeasurementSession {

    public enum Phase: Equatable {
        /// No usable fingertip yet. The countdown has not started.
        case awaitingContact(ContactIssue)
        /// Collecting. `progress` is 0...1 over the capture duration.
        case measuring(progress: Double, provisionalBPM: Double?)
        /// Enough signal, and the result cleared the confidence gate.
        case finished(PPGResult)
        /// Capture completed but the reading was not trustworthy.
        case needsRetake(PPGResult)
    }

    public private(set) var phase: Phase = .awaitingContact(.noFinger)

    private var samples: [FrameSample] = []
    private var contact = ContactMonitor()
    private let duration: TimeInterval
    /// Contact must be held this long before samples count, so the transient
    /// while the finger settles onto the lens does not enter the record.
    private let settleDuration: TimeInterval = 1.0
    private var contactStart: Double?

    public init(duration: TimeInterval = PPGConstants.measurementDuration) {
        self.duration = duration
    }

    /// Elapsed capture time in seconds, excluding any period without contact.
    public var elapsed: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return last.timestamp - first.timestamp
    }

    public func reset() {
        samples.removeAll(keepingCapacity: true)
        contact.reset()
        contactStart = nil
        phase = .awaitingContact(.noFinger)
    }

    /// Feed one frame. Returns the updated phase.
    @discardableResult
    public func ingest(_ sample: FrameSample) -> Phase {
        // Once a verdict is reached, further frames are ignored until reset.
        if case .finished = phase { return phase }
        if case .needsRetake = phase { return phase }

        if let issue = contact.evaluate(sample) {
            // Losing contact discards the record rather than stitching across
            // the gap: a splice would fabricate a beat interval that never
            // happened and corrupt the HRV figure.
            samples.removeAll(keepingCapacity: true)
            contactStart = nil
            phase = .awaitingContact(issue)
            return phase
        }

        if contactStart == nil { contactStart = sample.timestamp }
        guard let start = contactStart else { return phase }

        // Discard the settling period.
        guard sample.timestamp - start >= settleDuration else {
            phase = .measuring(progress: 0, provisionalBPM: nil)
            return phase
        }

        samples.append(sample)
        let progress = min(1.0, elapsed / duration)

        if elapsed >= duration {
            let result = analyzeAll()
            phase = result.isReportable ? .finished(result) : .needsRetake(result)
            return phase
        }

        phase = .measuring(progress: progress, provisionalBPM: provisionalEstimate())
        return phase
    }

    /// A rate shown mid-capture so the user sees progress.
    ///
    /// Computed over a trailing window rather than the whole record so it
    /// tracks the current rate, and suppressed below the confidence gate so a
    /// provisional number is never less trustworthy than a final one.
    private func provisionalEstimate() -> Double? {
        guard elapsed >= PPGConstants.provisionalAfterSeconds, let last = samples.last else {
            return nil
        }
        let cutoff = last.timestamp - PPGConstants.provisionalWindowSeconds
        let window = samples.filter { $0.timestamp >= cutoff }
        guard window.count >= 16 else { return nil }

        let result = PPGAnalyzer.analyze(timestamps: window.map(\.timestamp),
                                         values: window.map(\.red))
        return result.isReportable ? result.bpm : nil
    }

    private func analyzeAll() -> PPGResult {
        PPGAnalyzer.analyze(timestamps: samples.map(\.timestamp), values: samples.map(\.red))
    }
}
