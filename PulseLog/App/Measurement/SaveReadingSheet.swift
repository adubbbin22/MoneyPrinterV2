import PulseLogCore
import SwiftData
import SwiftUI

/// Shown once a measurement clears the confidence gate.
struct SaveReadingSheet: View {
    let reading: PendingReading
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tag: ContextTag = .resting
    @State private var note: String = ""

    private var band: HeartRateNorms.Band {
        HeartRateNorms.classifyResting(bpm: reading.bpm)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Text("\(Int(reading.bpm.rounded()))")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                        Text("beats per minute").foregroundStyle(.secondary)

                        if tag == .resting {
                            Text(band.displayName)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Theme.color(for: band).opacity(0.15))
                                .foregroundStyle(Theme.color(for: band))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                if let hrv = reading.hrvMs {
                    Section("Heart rate variability") {
                        LabeledContent("RMSSD", value: String(format: "%.0f ms", hrv))
                        Text("A measure of the variation between beats. It moves with "
                             + "rest, stress and recovery, and is most useful compared "
                             + "against your own history rather than to other people.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("What were you doing?") {
                    Picker("Context", selection: $tag) {
                        ForEach(ContextTag.allCases, id: \.self) { option in
                            Label(option.displayName, systemImage: option.symbolName).tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if let note = HeartRateNorms.note(for: reading.bpm, isResting: tag == .resting) {
                    Section { Text(note).font(.callout) }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical).lineLimit(1...4)
                }
            }
            .navigationTitle("Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { dismiss(); onSaved() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear { Haptics.success() }
    }

    private func save() {
        let record = StoredHeartRateReading(
            date: Date(), bpm: reading.bpm, hrvMs: reading.hrvMs,
            confidence: reading.confidence, tag: tag,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        context.insert(record)
        try? context.save()
        dismiss()
        onSaved()
    }
}
