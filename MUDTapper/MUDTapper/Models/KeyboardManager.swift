// Created for centralized keyboard handling across controllers
import UIKit

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


