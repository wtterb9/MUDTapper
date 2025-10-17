import UIKit

/// Centralized loading indicator utility for consistent async operation feedback
class LoadingIndicator {
    
    // MARK: - Shared Instance
    
    static let shared = LoadingIndicator()
    private init() {}
    
    // MARK: - Properties
    
    private var loadingView: UIView?
    private var activityIndicator: UIActivityIndicatorView?
    private var messageLabel: UILabel?
    
    // MARK: - Public Methods
    
    /// Show a loading indicator
    /// - Parameters:
    ///   - message: Optional message to display
    ///   - in: The view to display the loading indicator in (defaults to key window)
    func show(message: String? = nil, in view: UIView? = nil) {
        DispatchQueue.main.async {
            self.showLoadingView(message: message, in: view)
        }
    }
    
    /// Hide the loading indicator
    func hide() {
        DispatchQueue.main.async {
            self.hideLoadingView()
        }
    }
    
    /// Execute an async operation with loading indicator
    /// - Parameters:
    ///   - message: Loading message to display
    ///   - operation: The async operation to perform
    ///   - completion: Completion handler called when operation finishes
    static func perform<T>(
        message: String = "Loading...",
        operation: @escaping (@escaping (T) -> Void) -> Void,
        completion: @escaping (T) -> Void
    ) {
        shared.show(message: message)
        
        operation { result in
            shared.hide()
            completion(result)
        }
    }
    
    /// Execute an async operation that can fail
    /// - Parameters:
    ///   - message: Loading message
    ///   - operation: The operation (calls completion with Result)
    ///   - completion: Completion with Result type
    static func performWithResult<T>(
        message: String = "Loading...",
        operation: @escaping (@escaping (Result<T, Error>) -> Void) -> Void,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        shared.show(message: message)
        
        operation { result in
            shared.hide()
            completion(result)
        }
    }
    
    // MARK: - Private Implementation
    
    private func showLoadingView(message: String?, in containerView: UIView?) {
        // Remove any existing loading view first
        hideLoadingView()
        
        // Find the container view (default to key window)
        let container: UIView
        if let provided = containerView {
            container = provided
        } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first {
            container = window
        } else {
            Logger.warning("Unable to find container view for loading indicator", category: Logger.ui)
            return
        }
        
        // Create loading view
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        
        // Create activity indicator
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.color = .white
        indicator.startAnimating()
        
        view.addSubview(indicator)
        
        // Create message label if message provided
        if let message = message {
            let label = UILabel()
            label.text = message
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            
            view.addSubview(label)
            messageLabel = label
            
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                indicator.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
                
                label.topAnchor.constraint(equalTo: indicator.bottomAnchor, constant: 16),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
                
                view.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
                view.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
            ])
        } else {
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                
                view.widthAnchor.constraint(equalToConstant: 100),
                view.heightAnchor.constraint(equalToConstant: 100)
            ])
        }
        
        // Add to container
        container.addSubview(view)
        
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        
        loadingView = view
        activityIndicator = indicator
        
        // Accessibility
        view.isAccessibilityElement = true
        view.accessibilityLabel = message ?? "Loading"
        view.accessibilityTraits = .updatesFrequently
    }
    
    private func hideLoadingView() {
        loadingView?.removeFromSuperview()
        loadingView = nil
        activityIndicator = nil
        messageLabel = nil
    }
}

// MARK: - UIViewController Extension

extension UIViewController {
    
    /// Show loading indicator in this view controller's view
    /// - Parameter message: Optional loading message
    func showLoading(message: String? = nil) {
        LoadingIndicator.shared.show(message: message, in: view)
    }
    
    /// Hide loading indicator
    func hideLoading() {
        LoadingIndicator.shared.hide()
    }
}

