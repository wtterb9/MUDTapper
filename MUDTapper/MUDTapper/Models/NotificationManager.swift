import UIKit
import UserNotifications

class NotificationManager: NSObject {
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    // MARK: - Local Notifications
    
    func scheduleDisconnectionNotification(for worldName: String) {
        let content = UNMutableNotificationContent()
        content.title = "MUDTapper"
        content.body = "Disconnected from \(worldName)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "disconnect-\(worldName)",
            content: content,
            trigger: nil // Immediate notification
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    func scheduleReconnectionNotification(for worldName: String, delay: TimeInterval = 5.0) {
        let content = UNMutableNotificationContent()
        content.title = "MUDTapper"
        content.body = "Attempting to reconnect to \(worldName)..."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "reconnect-\(worldName)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling reconnection notification: \(error)")
            }
        }
    }
    
    func cancelNotifications(for worldName: String) {
        let identifiers = [
            "disconnect-\(worldName)",
            "reconnect-\(worldName)"
        ]
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               willPresent notification: UNNotification, 
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               didReceive response: UNNotificationResponse, 
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        let identifier = response.notification.request.identifier
        
        if identifier.hasPrefix("disconnect-") || identifier.hasPrefix("reconnect-") {
            // Bring app to foreground and potentially reconnect
            NotificationCenter.default.post(name: .notificationTapped, object: identifier)
        }
        
        completionHandler()
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let notificationTapped = Notification.Name("NotificationTappedNotification")
} 

// MARK: - Networking Preferences

enum NetworkingPreferences {
    private static let gmcpKey = "Networking.GMCPEnabled"
    private static let msdpKey = "Networking.MSDPEnabled"
    private static let mccpKey = "Networking.MCCPEnabled"
    private static let autoReconnectKey = "Networking.AutoReconnectEnabled"

    static var gmcpEnabled: Bool {
        get { UserDefaults.standard.object(forKey: gmcpKey) == nil ? true : UserDefaults.standard.bool(forKey: gmcpKey) }
        set { UserDefaults.standard.set(newValue, forKey: gmcpKey) }
    }

    static var msdpEnabled: Bool {
        get { UserDefaults.standard.object(forKey: msdpKey) == nil ? true : UserDefaults.standard.bool(forKey: msdpKey) }
        set { UserDefaults.standard.set(newValue, forKey: msdpKey) }
    }

    static var mccpEnabled: Bool {
        get { UserDefaults.standard.object(forKey: mccpKey) == nil ? true : UserDefaults.standard.bool(forKey: mccpKey) }
        set { UserDefaults.standard.set(newValue, forKey: mccpKey) }
    }

    static var autoReconnectEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoReconnectKey) == nil ? true : UserDefaults.standard.bool(forKey: autoReconnectKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoReconnectKey) }
    }
}
// MARK: - KeyboardManager (shared utility)

/// Centralized keyboard notification helper with simple closure callbacks.
class KeyboardManager {
    private let willShowCallback: (CGRect, Double, UInt) -> Void
    private let willHideCallback: (Double, UInt) -> Void

    init(willShow: @escaping (CGRect, Double, UInt) -> Void,
         willHide: @escaping (Double, UInt) -> Void) {
        self.willShowCallback = willShow
        self.willHideCallback = willHide

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func handleKeyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        willShowCallback(keyboardFrame, duration, curve)
    }

    @objc private func handleKeyboardWillHide(_ notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        willHideCallback(duration, curve)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}