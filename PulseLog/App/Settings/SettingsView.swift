import PulseLogCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var subscriptions: SubscriptionStore

    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("reminderMorningHour") private var morningHour = 8
    @AppStorage("reminderEveningHour") private var eveningHour = 20
    @State private var notificationsDenied = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Twice-daily reminders", isOn: $remindersEnabled)
                    if remindersEnabled {
                        Picker("Morning", selection: $morningHour) {
                            ForEach(4..<12) { Text(hourLabel($0)).tag($0) }
                        }
                        Picker("Evening", selection: $eveningHour) {
                            ForEach(17..<24) { Text(hourLabel($0)).tag($0) }
                        }
                    }
                } header: {
                    Text("Blood pressure reminders")
                } footer: {
                    // The reason for fixed times is the reason the feature
                    // exists, so it is stated rather than assumed.
                    Text("Blood pressure follows a daily rhythm, so readings taken at "
                         + "consistent times are the ones worth comparing. Morning "
                         + "readings are best taken before coffee or medication.")
                }

                if notificationsDenied {
                    Section {
                        Label("Notifications are turned off for PulseLog. Enable them "
                              + "in Settings to use reminders.", systemImage: "bell.slash")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    if health.isAuthorized {
                        Label("Connected", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Button("Connect Apple Health") {
                            Task { await health.requestAuthorization() }
                        }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("PulseLog writes your readings to Health, and reads sleep and "
                         + "step counts to explain what moves your resting heart rate. "
                         + "Without it, those insights can't be calculated.")
                }

                Section("Subscription") {
                    if subscriptions.isSubscribed {
                        Label("PulseLog Plus active", systemImage: "checkmark.seal")
                    } else {
                        Button("See PulseLog Plus") { showingPaywall = true }
                    }
                    Button("Restore purchases") {
                        Task { try? await subscriptions.restore() }
                    }
                }

                Section {
                    Text("PulseLog is a wellness tool, not a medical device. It does not "
                         + "diagnose, treat, or monitor any condition.\n\n"
                         + "It cannot measure blood pressure. No app can, using only a "
                         + "phone camera. Blood pressure readings here come from your own "
                         + "cuff, and are only as good as that cuff — check whether yours "
                         + "has been independently validated at validatebp.org.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .onChange(of: remindersEnabled) { _, enabled in
                Task { await applyReminders(enabled: enabled) }
            }
            .onChange(of: morningHour) { _, _ in
                Task { await applyReminders(enabled: remindersEnabled) }
            }
            .onChange(of: eveningHour) { _, _ in
                Task { await applyReminders(enabled: remindersEnabled) }
            }
        }
    }

    private func applyReminders(enabled: Bool) async {
        guard enabled else {
            Reminders.cancel()
            notificationsDenied = false
            return
        }
        guard await Reminders.requestAuthorization() else {
            // Reflect the real state rather than leaving a toggle on that does
            // nothing.
            notificationsDenied = true
            remindersEnabled = false
            return
        }
        notificationsDenied = false
        await Reminders.schedule(morning: DateComponents(hour: morningHour, minute: 0),
                                 evening: DateComponents(hour: eveningHour, minute: 0))
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
