import UIKit

/// Centralized error presentation utility for consistent user-facing error messages
class ErrorPresenter {
    
    // MARK: - Alert Presentation
    
    /// Present an error alert to the user
    /// - Parameters:
    ///   - title: The alert title
    ///   - message: The alert message
    ///   - error: Optional error to include in the message
    ///   - actions: Custom actions (defaults to OK button)
    static func showError(title: String, message: String, error: Error? = nil, actions: [UIAlertAction] = []) {
        var fullMessage = message
        
        if let error = error {
            fullMessage += "\n\nError: \(error.localizedDescription)"
        }
        
        let alert = UIAlertController(title: title, message: fullMessage, preferredStyle: .alert)
        
        if actions.isEmpty {
            alert.addAction(UIAlertAction(title: "OK", style: .default))
        } else {
            actions.forEach { alert.addAction($0) }
        }
        
        presentAlert(alert)
    }
    
    /// Present a success message to the user
    /// - Parameters:
    ///   - title: The alert title
    ///   - message: The alert message
    static func showSuccess(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlert(alert)
    }
    
    /// Present a warning message to the user
    /// - Parameters:
    ///   - title: The alert title
    ///   - message: The alert message
    ///   - continueAction: Action to perform if user chooses to continue
    ///   - cancelAction: Action to perform if user cancels (optional)
    static func showWarning(title: String, message: String, continueAction: @escaping () -> Void, cancelAction: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            cancelAction?()
        })
        
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
            continueAction()
        })
        
        presentAlert(alert)
    }
    
    /// Present a confirmation dialog
    /// - Parameters:
    ///   - title: The alert title
    ///   - message: The alert message
    ///   - confirmTitle: The confirmation button title (default: "Confirm")
    ///   - confirmStyle: The confirmation button style (default: .default)
    ///   - confirmAction: Action to perform if user confirms
    ///   - cancelAction: Action to perform if user cancels (optional)
    static func showConfirmation(
        title: String,
        message: String,
        confirmTitle: String = "Confirm",
        confirmStyle: UIAlertAction.Style = .default,
        confirmAction: @escaping () -> Void,
        cancelAction: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            cancelAction?()
        })
        
        alert.addAction(UIAlertAction(title: confirmTitle, style: confirmStyle) { _ in
            confirmAction()
        })
        
        presentAlert(alert)
    }
    
    // MARK: - Private Helpers
    
    /// Find the top-most view controller and present the alert
    private static func presentAlert(_ alert: UIAlertController) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController else {
                Logger.warning("Unable to find root view controller to present alert", category: Logger.ui)
                return
            }
            
            // Find the top-most presented view controller
            var presenter = rootViewController
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            
            presenter.present(alert, animated: true)
        }
    }
    
    // MARK: - Common Error Messages
    
    static func showNetworkError(_ error: Error) {
        showError(
            title: "Network Error",
            message: "Failed to connect to the server. Please check your internet connection and try again.",
            error: error
        )
    }
    
    static func showDatabaseError(_ error: Error) {
        showError(
            title: "Database Error",
            message: "A database error occurred. Your data may not have been saved.",
            error: error
        )
    }
    
    static func showValidationError(_ message: String) {
        showError(
            title: "Validation Error",
            message: message
        )
    }
    
    static func showGenericError(_ error: Error) {
        showError(
            title: "Error",
            message: "An unexpected error occurred.",
            error: error
        )
    }
}

