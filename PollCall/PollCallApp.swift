import SwiftUI
import UserNotifications

@main
struct PollCallApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = VotingModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .fontDesign(.rounded)
                .tint(Brand.ink)
        }
    }
}

/// Handles notification presentation and the "I voted" action on the notification itself.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ReminderScheduler.registerCategories()
        return true
    }

    // Show reminders even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Long-press a reminder and tap "I voted" — no need to open the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == ReminderScheduler.votedAction {
            ReminderScheduler.markVoted()
        }
    }
}
