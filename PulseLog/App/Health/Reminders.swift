import Foundation
import UserNotifications

/// Twice-daily reminders to log blood pressure.
///
/// Timing is the point, not the nagging. Blood pressure follows a daily
/// rhythm, so home-monitoring guidance asks for readings at consistent times —
/// morning and evening. A reminder at a fixed hour is what makes a home log
/// comparable with itself over weeks.
@MainActor
enum Reminders {
    private static let morningID = "pulselog.bp.morning"
    private static let eveningID = "pulselog.bp.evening"

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(morning: DateComponents, evening: DateComponents) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningID, eveningID])

        await add(id: morningID, at: morning, title: "Morning reading",
                  body: "Take your blood pressure before coffee or medication, "
                      + "sitting quietly for five minutes first.")
        await add(id: eveningID, at: evening, title: "Evening reading",
                  body: "Time for your evening blood pressure reading.")
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [morningID, eveningID])
    }

    private static func add(id: String, at time: DateComponents,
                            title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
