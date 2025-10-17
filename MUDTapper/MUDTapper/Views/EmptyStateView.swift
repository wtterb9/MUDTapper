import UIKit

/// A reusable empty state view for displaying when lists/collections have no content
class EmptyStateView: UIView {
    
    // MARK: - Properties
    
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stackView = UIStackView()
    
    private var buttonAction: (() -> Void)?
    
    // MARK: - Initialization
    
    init() {
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = .clear
        
        // Configure image view
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemGray
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure title label
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure message label
        messageLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure action button
        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.isHidden = true
        
        // Configure stack view
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(actionButton)
        
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            
            actionButton.heightAnchor.constraint(equalToConstant: 44),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
    }
    
    // MARK: - Configuration
    
    /// Configure the empty state view
    /// - Parameters:
    ///   - image: System image name or nil
    ///   - title: Main title text
    ///   - message: Descriptive message text
    ///   - buttonTitle: Action button title (nil to hide button)
    ///   - buttonAction: Action to perform when button is tapped
    func configure(
        image: String? = nil,
        title: String,
        message: String,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) {
        // Set image
        if let imageName = image {
            imageView.image = UIImage(systemName: imageName)
            imageView.isHidden = false
        } else {
            imageView.isHidden = true
        }
        
        // Set title
        titleLabel.text = title
        
        // Set message
        messageLabel.text = message
        
        // Set button
        if let buttonTitle = buttonTitle {
            actionButton.setTitle(buttonTitle, for: .normal)
            actionButton.isHidden = false
            self.buttonAction = buttonAction
        } else {
            actionButton.isHidden = true
            self.buttonAction = nil
        }
    }
    
    /// Apply theme colors to the empty state view
    /// - Parameter themeManager: The theme manager to use for colors
    func applyTheme(_ themeManager: ThemeManager) {
        imageView.tintColor = themeManager.terminalTextColor.withAlphaComponent(0.4)
        titleLabel.textColor = themeManager.terminalTextColor
        messageLabel.textColor = themeManager.terminalTextColor.withAlphaComponent(0.7)
        actionButton.tintColor = themeManager.linkColor
    }
    
    // MARK: - Actions
    
    @objc private func actionButtonTapped() {
        buttonAction?()
    }
    
    // MARK: - Convenience Factory Methods
    
    /// Create an empty state for no worlds
    static func noWorlds(action: @escaping () -> Void) -> EmptyStateView {
        let view = EmptyStateView()
        view.configure(
            image: "globe.badge.chevron.backward",
            title: "No Worlds",
            message: "You haven't added any MUD worlds yet.\nTap the button below to get started.",
            buttonTitle: "Add World",
            buttonAction: action
        )
        return view
    }
    
    /// Create an empty state for no triggers
    static func noTriggers(action: @escaping () -> Void) -> EmptyStateView {
        let view = EmptyStateView()
        view.configure(
            image: "bolt.fill",
            title: "No Triggers",
            message: "Create triggers to automate responses to server text.",
            buttonTitle: "Add Trigger",
            buttonAction: action
        )
        return view
    }
    
    /// Create an empty state for no aliases
    static func noAliases(action: @escaping () -> Void) -> EmptyStateView {
        let view = EmptyStateView()
        view.configure(
            image: "command",
            title: "No Aliases",
            message: "Create aliases to expand short commands into longer sequences.",
            buttonTitle: "Add Alias",
            buttonAction: action
        )
        return view
    }
    
    /// Create an empty state for search with no results
    static func noSearchResults(searchTerm: String) -> EmptyStateView {
        let view = EmptyStateView()
        view.configure(
            image: "magnifyingglass",
            title: "No Results",
            message: "No items match '\(searchTerm)'\nTry a different search term."
        )
        return view
    }
    
    /// Create an empty state for no connection
    static func noConnection() -> EmptyStateView {
        let view = EmptyStateView()
        view.configure(
            image: "wifi.slash",
            title: "Not Connected",
            message: "Connect to a world to see output."
        )
        return view
    }
}

