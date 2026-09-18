import Foundation
import UserNotifications
import TimeSeriesKit

/// Central manager for macOS system desktop notifications on network SLA breaches
public final class NotificationManager: @unchecked Sendable {
    public static let shared = NotificationManager()

    private let userDefaultsKey = "nexwave.notifications.sla.enabled"
    private var isAuthorized: Bool = false

    public var isNotificationsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            if newValue {
                requestAuthorization()
            }
        }
    }

    public init() {
        requestAuthorization()
    }

    /// Requests macOS notification permissions gracefully
    public func requestAuthorization(completion: (@Sendable (Bool) -> Void)? = nil) {
        guard Bundle.main.bundleIdentifier != nil else {
            completion?(false)
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.isAuthorized = true
                completion?(true)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    self.isAuthorized = granted
                    if let error = error {
                        print("[NotificationManager] Authorization failed: \(error.localizedDescription)")
                    }
                    completion?(granted)
                }
            case .denied:
                self.isAuthorized = false
                completion?(false)
            @unknown default:
                self.isAuthorized = false
                completion?(false)
            }
        }
    }

    /// Dispatches an immediate desktop notification banner for an SLA breach
    public func postSLAAlert(_ alert: SLAMonitorAlert) {
        guard isNotificationsEnabled else { return }
        guard Bundle.main.bundleIdentifier != nil else { return }

        let content = UNMutableNotificationContent()
        content.title = "⚠️ SLA Breach: \(alert.targetName)"
        content.subtitle = alert.alertType.rawValue
        content.body = alert.message
        content.sound = .default
        content.userInfo = [
            "target": alert.target,
            "targetName": alert.targetName,
            "alertId": alert.id.uuidString,
            "alertType": alert.alertType.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "sla_alert_\(alert.id.uuidString)",
            content: content,
            trigger: nil // Dispatch immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] Failed to deliver SLA banner: \(error.localizedDescription)")
            }
        }
    }
}
