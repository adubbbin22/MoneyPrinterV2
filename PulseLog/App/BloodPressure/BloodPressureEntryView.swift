import PulseLogCore
import SwiftData
import SwiftUI

/// Manual blood-pressure entry.
///
/// Manual is the whole design. There is no validated way to measure blood
/// pressure with a phone camera, so this screen records what a real cuff
/// reported and never pretends to produce it.
struct BloodPressureEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var systolic = 120
    @State private var diastolic = 80
    @State private var pulse: Int?
    @State private var tag: ContextTag = .resting
    @State private var note = ""
    @State private var date = Date()

    private var category: BloodPressureCategory {
        BloodPressureCategory.classify(systolic: systolic, diastolic: diastolic)
    }

    private var problem: BloodPressureValidation.Problem? {
        BloodPressureValidation.validate(systolic: systolic, diastolic: diastolic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("Systolic", selection: $systolic) {
                            ForEach(BloodPressureValidation.systolicRange, id: \.self) {
                                Text("\($0)").tag($0)
                            }
                        }
                        .pickerStyle(.wheel).frame(maxWidth: .infinity)

                        Text("/").font(.title).foregroundStyle(.secondary)

                        Picker("Diastolic", selection: $diastolic) {
                            ForEach(BloodPressureValidation.diastolicRange, id: \.self) {
                                Text("\($0)").tag($0)
                            }
                        }
                        .pickerStyle(.wheel).frame(maxWidth: .infinity)
                    }
                    .frame(height: 160)

                    if let problem {
                        Label(problem.message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    } else {
                        CategoryBadge(category: category)
                            .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text("mmHg")
                }

                if category.requiresUrgentAttention, let message = category.urgentMessage {
                    Section {
                        Label {
                            Text(message).font(.callout)
                        } icon: {
                            Image(systemName: "exclamationmark.octagon.fill")
                        }
                        .foregroundStyle(Theme.color(for: .crisis))
                    }
                }

                Section("Details") {
                    DatePicker("When", selection: $date, in: ...Date())
                    Picker("Context", selection: $tag) {
                        ForEach(ContextTag.allCases, id: \.self) { option in
                            Label(option.displayName, systemImage: option.symbolName).tag(option)
                        }
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                }

                Section {
                    Text("Enter readings from a validated upper-arm cuff. Wrist and "
                         + "finger cuffs are less reliable. You can check whether "
                         + "your device has been independently validated at "
                         + "validatebp.org.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Log blood pressure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(problem != nil)
                }
            }
        }
    }

    private func save() {
        guard problem == nil else { return }
        let record = StoredBloodPressureReading(
            date: date, systolic: systolic, diastolic: diastolic, pulse: pulse, tag: tag,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        )
        context.insert(record)
        try? context.save()
        if category.requiresUrgentAttention { Haptics.warning() } else { Haptics.success() }
        dismiss()
    }
}

struct CategoryBadge: View {
    let category: BloodPressureCategory

    var body: some View {
        VStack(spacing: 4) {
            Text(category.displayName)
                .font(.headline)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Theme.color(for: category).opacity(0.15))
                .foregroundStyle(Theme.color(for: category))
                .clipShape(Capsule())
            Text(category.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
