import Foundation
import UserNotifications
import AutomationCore

@MainActor
final class NotificationService {
    private var sent: [String: Date] = [:]
    func send(key: String, text: String, enabled: Bool) {
        guard enabled, ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] == nil, Bundle.main.bundleIdentifier != nil else { return }
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
        Task { _ = await permissionStatus(requestIfNeeded: true) }
    }
    func permissionStatus(requestIfNeeded: Bool) async -> PermissionDecision {
        guard ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] == nil else { return .granted }
        guard Bundle.main.bundleIdentifier != nil else { return .undetermined }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined:
            guard requestIfNeeded else { return .undetermined }
            do { return try await center.requestAuthorization(options: [.alert, .sound]) ? .granted : .denied }
            catch { return .denied }
        @unknown default: return .undetermined
        }
    }
}
