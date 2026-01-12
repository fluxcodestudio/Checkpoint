import Cocoa
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private let menuBarManager = MenuBarManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set as menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager()

        // Setup menu bar
        menuBarManager.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
