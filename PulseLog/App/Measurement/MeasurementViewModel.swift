import Foundation
import PulseLogCore
import PulseLogSignal
import SwiftUI

@MainActor
final class MeasurementViewModel: ObservableObject {

    enum Screen: Equatable {
        case idle
        case starting
        case awaitingContact(ContactIssue)
        case measuring(progress: Double, provisionalBPM: Double?)
        case result(bpm: Double, hrvMs: Double?, confidence: Double)
        case retake(reason: String)
        case failed(message: String)
    }

    @Published private(set) var screen: Screen = .idle
    @Published private(set) var currentFact: String = ""
    /// Beat pulses for the animated heart, published as they are detected.
    @Published private(set) var beatTick: Int = 0

    private let camera = CameraController()
    private var session = MeasurementSession()
    private var facts: [String] = []
    private var factIndex = 0
    private var lastFactChange: Date = .distantPast
    private var lastBeatAt: Date = .distantPast

    /// How long a fact stays on screen. Long enough to read a sentence
    /// without feeling like a slideshow.
    private let factInterval: TimeInterval = 6.0

    // MARK: - Lifecycle

    func begin() async {
        screen = .starting
        facts = CardiovascularFacts.sequence()
        factIndex = 0
        currentFact = facts.first ?? ""
        lastFactChange = Date()
        session.reset()

        camera.onSample = { [weak self] sample in
            self?.handle(sample)
        }

        do {
            try await camera.start()
            screen = .awaitingContact(.noFinger)
        } catch {
            screen = .failed(message: error.localizedDescription)
        }
    }

    func end() {
        camera.stop()
        camera.onSample = nil
        screen = .idle
    }

    func restart() async {
        session.reset()
        factIndex = 0
        currentFact = facts.first ?? ""
        screen = .awaitingContact(.noFinger)
    }

    // MARK: - Frame handling

    private func handle(_ sample: FrameSample) {
        let phase = session.ingest(sample)
        advanceFactIfNeeded()

        switch phase {
        case .awaitingContact(let issue):
            screen = .awaitingContact(issue)

        case .measuring(let progress, let provisional):
            screen = .measuring(progress: progress, provisionalBPM: provisional)
            tickHeartIfDue(provisional)

        case .finished(let result):
            guard let bpm = result.bpm else {
                screen = .retake(reason: "That reading wasn't clear enough.")
                return
            }
            camera.stop()
            screen = .result(bpm: bpm, hrvMs: result.rmssdMs, confidence: result.confidence)

        case .needsRetake:
            camera.stop()
            // Never dress a rejected reading up as a number. Say what to change.
            screen = .retake(reason: "The signal wasn't steady enough to trust. "
                             + "Rest your finger gently over both the camera and the "
                             + "flash, keep still, and try again.")
        }
    }

    /// Drive the heart animation at the estimated rate.
    ///
    /// Animating at a fixed rate would be a lie the user can feel; animating
    /// at the measured rate is what makes the reading feel real.
    private func tickHeartIfDue(_ bpm: Double?) {
        guard let bpm, bpm > 0 else { return }
        let interval = 60.0 / bpm
        guard Date().timeIntervalSince(lastBeatAt) >= interval else { return }
        lastBeatAt = Date()
        beatTick &+= 1
    }

    private func advanceFactIfNeeded() {
        guard !facts.isEmpty, Date().timeIntervalSince(lastFactChange) >= factInterval else { return }
        factIndex = (factIndex + 1) % facts.count
        currentFact = facts[factIndex]
        lastFactChange = Date()
    }
}
