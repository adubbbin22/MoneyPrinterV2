import PulseLogCore
import PulseLogSignal
import SwiftUI

struct MeasurementView: View {
    @StateObject private var model = MeasurementViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var pendingResult: PendingReading?

    var body: some View {
        ZStack {
            Theme.pageBackground.ignoresSafeArea()
            content
                .padding()
        }
        .navigationTitle("Measure")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.begin() }
        .onDisappear { model.end() }
        .sheet(item: $pendingResult) { reading in
            SaveReadingSheet(reading: reading) { dismiss() }
        }
        .onChange(of: model.screen) { _, screen in
            if case .result(let bpm, let hrv, let confidence) = screen {
                pendingResult = PendingReading(bpm: bpm, hrvMs: hrv, confidence: confidence)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .idle, .starting:
            ProgressView("Starting camera…")

        case .failed(let message):
            StatusMessageView(symbol: "exclamationmark.triangle",
                              title: "Can't measure",
                              message: message)

        case .awaitingContact(let issue):
            VStack(spacing: 28) {
                FingerGuideView()
                Text(issue.guidance)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("Rest your fingertip over the rear camera and flash. "
                     + "Cover both, and press only lightly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .measuring(let progress, let provisional):
            VStack(spacing: 32) {
                PulsingHeartView(bpm: provisional, beatTick: model.beatTick, progress: progress)
                if let provisional {
                    Text("\(Int(provisional.rounded()))")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("BPM so far")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Reading your pulse…")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                FactCardView(text: model.currentFact)
            }

        case .retake(let reason):
            VStack(spacing: 24) {
                StatusMessageView(symbol: "arrow.clockwise.heart",
                                  title: "Let's try that again",
                                  message: reason)
                Button("Measure again") {
                    Task { await model.restart() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }

        case .result:
            ProgressView()
        }
    }
}

/// The animated heart and progress ring.
struct PulsingHeartView: View {
    let bpm: Double?
    let beatTick: Int
    let progress: Double

    @State private var scale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)

            Image(systemName: "heart.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 92)
                .foregroundStyle(Theme.accent)
                .scaleEffect(scale)
        }
        .frame(width: 220, height: 220)
        .onChange(of: beatTick) { _, _ in
            // Driven by detected beats rather than a fixed timer, so the
            // animation matches the pulse actually being measured.
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.12)) { scale = 1.14 }
            withAnimation(.easeIn(duration: 0.22).delay(0.12)) { scale = 1.0 }
        }
        .accessibilityLabel("Measuring")
        .accessibilityValue(bpm.map { "\(Int($0.rounded())) beats per minute so far" }
                            ?? "Still reading your pulse")
    }
}

struct FactCardView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("While you wait", systemImage: "lightbulb")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.4), value: text)
    }
}

struct FingerGuideView: View {
    var body: some View {
        Image(systemName: "hand.point.up.left.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 110)
            .foregroundStyle(Theme.accent.opacity(0.85))
            .accessibilityHidden(true)
    }
}

struct StatusMessageView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct PendingReading: Identifiable {
    let id = UUID()
    let bpm: Double
    let hrvMs: Double?
    let confidence: Double
}
