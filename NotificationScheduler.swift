import Foundation
import UserNotifications

extension Notification.Name {
    static let brainNoteReminderOpened = Notification.Name(
        "BrainNoteReminderOpened"
    )
}

final class BrainNoteNotificationRouter: NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let shared = BrainNoteNotificationRouter()

    private let pendingNoteIDKey = "pendingBrainNoteNotificationID"

    private override init() {
        super.init()
    }

    func start(center: UNUserNotificationCenter = .current()) {
        center.delegate = self
    }

    func pendingNoteID() -> UUID? {
        guard let rawValue = UserDefaults.standard.string(forKey: pendingNoteIDKey) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    func clearPendingNoteID(_ noteID: UUID) {
        guard pendingNoteID() == noteID else { return }
        UserDefaults.standard.removeObject(forKey: pendingNoteIDKey)
        UserDefaults.standard.synchronize()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let noteID = Self.noteID(from: response.notification.request.content) else {
            return
        }

        UserDefaults.standard.set(noteID.uuidString, forKey: pendingNoteIDKey)
        UserDefaults.standard.synchronize()

        await MainActor.run {
            NotificationCenter.default.post(
                name: .brainNoteReminderOpened,
                object: noteID
            )
        }
    }

    private static func noteID(from content: UNNotificationContent) -> UUID? {
        guard let rawValue = content.userInfo["brainNoteID"] as? String else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }
}

@MainActor
final class NotificationScheduler {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        BrainNoteNotificationRouter.shared.start(center: center)
    }

    func scheduleReminder(for note: BrainNote) async throws {
        guard note.lifecycleState == .active,
              note.category == .actionable,
              !note.isCompleted,
              let eventDate = note.eventDate,
              eventDate > Date() else {
            cancelReminder(for: note)
            return
        }

        guard try await canScheduleNotifications() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming action"
        content.body = note.rawText
        content.sound = .default
        content.threadIdentifier = "brain-note-reminders"
        content.targetContentIdentifier = note.id.uuidString
        content.userInfo = ["brainNoteID": note.id.uuidString]

        var dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: eventDate
        )
        dateComponents.timeZone = .current

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: note),
            content: content,
            trigger: trigger
        )

        try await center.add(request)
    }

    func cancelReminder(for note: BrainNote) {
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: note)]
        )
    }

    private func canScheduleNotifications() async throws -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func notificationIdentifier(for note: BrainNote) -> String {
        "brain-note-\(note.id.uuidString)"
    }
}
