import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    private var sent: [String: Date] = [:]
    func send(key: String, text: String, enabled: Bool) {
        guard enabled, Bundle.main.bundleIdentifier != nil else { return }
        if let previous = sent[key], Date().timeIntervalSince(previous) < 300 { return }
        sent[key] = Date()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Subler Automation"; content.body = text
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
    }
    func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
