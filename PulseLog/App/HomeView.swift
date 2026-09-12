import PulseLogCore
import SwiftData
import SwiftUI

struct HomeView: View {
    var onFirstMeasurementSaved: () -> Void

    @EnvironmentObject private var health: HealthKitBridge

    @Query(sort: \StoredHeartRateReading.date, order: .reverse)
    private var heartRates: [StoredHeartRateReading]
    @Query(sort: \StoredBloodPressureReading.date, order: .reverse)
    private var bloodPressures: [StoredBloodPressureReading]

    @State private var showingMeasure = false
    @State private var showingBloodPressure = false
    @State private var countAtAppear = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let latest = heartRates.first {
                        LatestHeartRateCard(reading: latest.value)
                    }
                    if let latest = bloodPressures.first {
                        LatestBloodPressureCard(reading: latest.value)
                    }
                    if heartRates.isEmpty && bloodPressures.isEmpty {
                        WelcomeCard()
                    }

                    Button {
                        showingMeasure = true
                    } label: {
                        Label("Measure heart rate", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accent)

                    Button {
                        showingBloodPressure = true
                    } label: {
                        Label("Log blood pressure", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
            .background(Theme.pageBackground)
            .navigationTitle("PulseLog")
            .navigationDestination(isPresented: $showingMeasure) { MeasurementView(health: health) }
            .sheet(isPresented: $showingBloodPressure) { BloodPressureEntryView() }
            .onAppear { countAtAppear = heartRates.count }
            .onChange(of: heartRates.count) { previous, current in
                // The paywall is offered only once the user has a result in
                // hand, so the value is concrete rather than promised.
                if current > previous, current == 1 { onFirstMeasurementSaved() }
            }
        }
    }
}

struct LatestHeartRateCard: View {
    let reading: HeartRateReading

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest heart rate").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(reading.bpm.rounded()))")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("BPM").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Label(reading.tag.displayName, systemImage: reading.tag.symbolName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(reading.date, format: .relative(presentation: .named))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct LatestBloodPressureCard: View {
    let reading: BloodPressureReading

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest blood pressure").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(reading.systolic)/\(reading.diastolic)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("mmHg").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Text(reading.category.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.color(for: reading.category).opacity(0.15))
                    .foregroundStyle(Theme.color(for: reading.category))
                    .clipShape(Capsule())
            }
            Text(reading.date, format: .relative(presentation: .named))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct WelcomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Take your first reading").font(.headline)
            Text("Rest a fingertip over the rear camera and flash, covering both, and "
                 + "hold still for 30 seconds.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
