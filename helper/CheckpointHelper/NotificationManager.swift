import Foundation
import UserNotifications

/// Manages system notifications for Checkpoint events
class NotificationManager: NSObject {

    // MARK: - Init

    override init() {
        super.init()
        requestAuthorization()
    }

    // MARK: - Authorization

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    // MARK: - Show Notifications

    func showNotification(title: String, body: String, identifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let id = identifier ?? UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show notification: \(error)")
            }
        }
    }

    func showBackupComplete(project: String, fileCount: Int) {
        showNotification(
            title: "Backup Complete",
            body: "\(project): \(fileCount) files backed up",
            identifier: "backup-complete-\(project)"
        )
    }

    func showBackupError(project: String, error: String) {
        showNotification(
            title: "Backup Failed",
            body: "\(project): \(error)",
            identifier: "backup-error-\(project)"
        )
    }

    func showDaemonStatus(running: Bool) {
        if running {
            showNotification(
                title: "Checkpoint Active",
                body: "Backup daemon is running",
                identifier: "daemon-status"
            )
        } else {
            showNotification(
                title: "Checkpoint Inactive",
                body: "Backup daemon is not running",
                identifier: "daemon-status"
            )
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap - open dashboard
        DaemonController.openDashboard()
        completionHandler()
    }
}
