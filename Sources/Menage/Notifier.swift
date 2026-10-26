import Foundation
import MenageCore
import UserNotifications

/// Notifications macOS. Inactif hors d'un bundle `.app` (`swift run`) : le centre de
/// notifications refuse les exécutables nus.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ alert: Alert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        if alert.level == .critique { content.sound = .default }
        // Un identifiant par signal : une nouvelle alerte disque remplace l'ancienne au lieu de s'empiler.
        center?.add(UNNotificationRequest(identifier: "menage.\(alert.signal.rawValue)", content: content, trigger: nil))
    }

    func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func postTest() {
        let content = UNMutableNotificationContent()
        content.title = "Ménage"
        content.body = "Les notifications fonctionnent. Tu seras prévenu quand le disque ou la mémoire deviennent critiques."
        center?.add(UNNotificationRequest(identifier: "menage.test", content: content, trigger: nil))
    }

    /// Affiche la bannière même quand le panneau de Ménage est ouvert.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
