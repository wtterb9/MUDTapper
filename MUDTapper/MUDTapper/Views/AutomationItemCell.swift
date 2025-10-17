import UIKit

class AutomationItemCell: UITableViewCell {
    
    // MARK: - UI Components
    
    private let containerView = UIView()
    private let nameLabel = UILabel()
    private let patternLabel = UILabel()
    private let actionLabel = UILabel()
    private let statusStackView = UIStackView()
    private let enabledIndicator = UIView()
    private let activeIndicator = UIView()
    private let statsLabel = UILabel()
    private let typeIconImageView = UIImageView()
    private let quickToggleButton = UIButton()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        selectionStyle = .default
        
        setupContainerView()
        setupLabels()
        setupStatusIndicators()
        setupButtons()
        setupConstraints()
    }
    
    private func setupContainerView() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.secondarySystemBackground
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.separator.cgColor
        
        contentView.addSubview(containerView)
    }
    
    private func setupLabels() {
        // Name label
        nameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Pattern label (with syntax highlighting)
        patternLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        patternLabel.textColor = .systemBlue
        patternLabel.numberOfLines = 2
        patternLabel.lineBreakMode = .byTruncatingTail
        patternLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Action label
        actionLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        actionLabel.textColor = .secondaryLabel
        actionLabel.numberOfLines = 2
        actionLabel.lineBreakMode = .byTruncatingTail
        actionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Stats label
        statsLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        statsLabel.textColor = .tertiaryLabel
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Type icon
        typeIconImageView.translatesAutoresizingMaskIntoConstraints = false
        typeIconImageView.tintColor = .systemBlue
        typeIconImageView.contentMode = .scaleAspectFit
        
        containerView.addSubview(nameLabel)
        containerView.addSubview(patternLabel)
        containerView.addSubview(actionLabel)
        containerView.addSubview(statsLabel)
        containerView.addSubview(typeIconImageView)
    }
    
    private func setupStatusIndicators() {
        // Enabled indicator
        enabledIndicator.translatesAutoresizingMaskIntoConstraints = false
        enabledIndicator.layer.cornerRadius = 4
        enabledIndicator.backgroundColor = .systemGreen
        
        // Active indicator
        activeIndicator.translatesAutoresizingMaskIntoConstraints = false
        activeIndicator.layer.cornerRadius = 4
        activeIndicator.backgroundColor = .systemOrange
        
        // Status stack view
        statusStackView.axis = .horizontal
        statusStackView.spacing = 4
        statusStackView.alignment = .center
        statusStackView.translatesAutoresizingMaskIntoConstraints = false
        statusStackView.addArrangedSubview(enabledIndicator)
        statusStackView.addArrangedSubview(activeIndicator)
        
        containerView.addSubview(statusStackView)
    }
    
    private func setupButtons() {
        quickToggleButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = "Toggle"
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        config.baseForegroundColor = .systemBlue
        config.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.1)
        quickToggleButton.configuration = config
        quickToggleButton.addTarget(self, action: #selector(quickToggleButtonTapped), for: .touchUpInside)
        
        containerView.addSubview(quickToggleButton)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Container view
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            // Type icon
            typeIconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            typeIconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            typeIconImageView.widthAnchor.constraint(equalToConstant: 20),
            typeIconImageView.heightAnchor.constraint(equalToConstant: 20),
            
            // Name label
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: typeIconImageView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: quickToggleButton.leadingAnchor, constant: -8),
            
            // Quick toggle button
            quickToggleButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            quickToggleButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            quickToggleButton.heightAnchor.constraint(equalToConstant: 24),
            
            // Pattern label
            patternLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            patternLabel.leadingAnchor.constraint(equalTo: typeIconImageView.trailingAnchor, constant: 8),
            patternLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            // Action label
            actionLabel.topAnchor.constraint(equalTo: patternLabel.bottomAnchor, constant: 4),
            actionLabel.leadingAnchor.constraint(equalTo: typeIconImageView.trailingAnchor, constant: 8),
            actionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            // Status stack view
            statusStackView.topAnchor.constraint(equalTo: actionLabel.bottomAnchor, constant: 8),
            statusStackView.leadingAnchor.constraint(equalTo: typeIconImageView.trailingAnchor, constant: 8),
            
            // Status indicators
            enabledIndicator.widthAnchor.constraint(equalToConstant: 8),
            enabledIndicator.heightAnchor.constraint(equalToConstant: 8),
            activeIndicator.widthAnchor.constraint(equalToConstant: 8),
            activeIndicator.heightAnchor.constraint(equalToConstant: 8),
            
            // Stats label
            statsLabel.topAnchor.constraint(equalTo: actionLabel.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: statusStackView.trailingAnchor, constant: 8),
            statsLabel.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -12),
            statsLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with item: AdvancedAutomationViewController.AutomationItem) {
        nameLabel.text = item.name
        patternLabel.text = item.pattern
        actionLabel.text = item.action
        
        // Type icon
        typeIconImageView.image = UIImage(systemName: item.type.icon)
        
        // Accessibility
        setupAccessibility(for: item)
        
        // Status indicators
        enabledIndicator.backgroundColor = item.isEnabled ? .systemGreen : .systemRed
        activeIndicator.backgroundColor = item.isActive ? .systemOrange : .systemGray4
        activeIndicator.isHidden = !item.isEnabled
        
        // Stats
        if item.triggerCount > 0 {
            let lastTriggeredText = item.lastTriggered?.timeAgoDisplay ?? "Never"
            statsLabel.text = "Used \(item.triggerCount)× • Last: \(lastTriggeredText)"
        } else {
            statsLabel.text = "Never triggered"
        }
        
        // Quick toggle button
        var buttonConfig = quickToggleButton.configuration ?? UIButton.Configuration.filled()
        buttonConfig.title = item.isEnabled ? "Disable" : "Enable"
        buttonConfig.baseBackgroundColor = item.isEnabled ?
            UIColor.systemRed.withAlphaComponent(0.1) :
            UIColor.systemGreen.withAlphaComponent(0.1)
        buttonConfig.baseForegroundColor = item.isEnabled ? .systemRed : .systemGreen
        quickToggleButton.configuration = buttonConfig
        
        // Container border color based on status
        containerView.layer.borderColor = item.isEnabled ? 
            UIColor.systemGreen.withAlphaComponent(0.3).cgColor : 
            UIColor.separator.cgColor
        
        // Apply syntax highlighting to pattern
        applySyntaxHighlighting(to: patternLabel, text: item.pattern, type: item.type)
    }
    
    private func applySyntaxHighlighting(to label: UILabel, text: String, type: AdvancedAutomationViewController.AutomationType) {
        let attributedString = NSMutableAttributedString(string: text)
        
        // Base attributes
        attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: NSRange(location: 0, length: text.count))
        attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: text.count))
        
        switch type {
        case .triggers:
            // Highlight regex special characters
            highlightRegexPatterns(in: attributedString, text: text)
            
        case .aliases:
            // Highlight variables ($1, $2, etc.)
            highlightVariables(in: attributedString, text: text)
            
        case .gags:
            // Highlight pattern syntax
            highlightPatterns(in: attributedString, text: text)
            
        case .tickers:
            // Highlight time intervals
            highlightTimeValues(in: attributedString, text: text)
        }
        
        label.attributedText = attributedString
    }
    
    private func highlightRegexPatterns(in attributedString: NSMutableAttributedString, text: String) {
        let regexChars = CharacterSet(charactersIn: ".*+?^${}[]|()")
        let nsString = text as NSString
        
        for i in 0..<nsString.length {
            let char = nsString.character(at: i)
            if regexChars.contains(UnicodeScalar(char)!) {
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemRed, range: NSRange(location: i, length: 1))
                attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: NSRange(location: i, length: 1))
            }
        }
    }
    
    private func highlightVariables(in attributedString: NSMutableAttributedString, text: String) {
        let pattern = "\\$\\d+"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: match.range)
                attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: match.range)
            }
        } catch {
            // Handle regex error
        }
    }
    
    private func highlightPatterns(in attributedString: NSMutableAttributedString, text: String) {
        // Simple pattern highlighting
        if text.contains("*") {
            let nsString = text as NSString
            var searchRange = NSRange(location: 0, length: nsString.length)
            
            while searchRange.location < nsString.length {
                let foundRange = nsString.range(of: "*", options: [], range: searchRange)
                if foundRange.location != NSNotFound {
                    attributedString.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: foundRange)
                    attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: foundRange)
                    searchRange = NSRange(location: foundRange.location + foundRange.length, length: nsString.length - foundRange.location - foundRange.length)
                } else {
                    break
                }
            }
        }
    }
    
    private func highlightTimeValues(in attributedString: NSMutableAttributedString, text: String) {
        let pattern = "\\d+(?:\\.\\d+)?"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            
            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: match.range)
                attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 14, weight: .bold), range: match.range)
            }
        } catch {
            // Handle regex error
        }
    }
    
    // MARK: - Accessibility
    
    private func setupAccessibility(for item: AdvancedAutomationViewController.AutomationItem) {
        // Make the entire cell accessible
        isAccessibilityElement = false
        containerView.isAccessibilityElement = true
        
        // Create comprehensive accessibility label
        let statusText = item.isEnabled ? "enabled" : "disabled"
        let activeText = item.isActive ? "active" : "inactive"
        let countText = item.triggerCount > 0 ? "triggered \(item.triggerCount) times" : "never triggered"
        
        containerView.accessibilityLabel = """
        \(item.type.singularTitle): \(item.name)
        Pattern: \(item.pattern)
        Action: \(item.action)
        Status: \(statusText), \(activeText)
        \(countText)
        """
        
        containerView.accessibilityHint = "Double tap to view options. Contains quick toggle button."
        containerView.accessibilityTraits = .button
        
        // Quick toggle button accessibility
        quickToggleButton.isAccessibilityElement = true
        quickToggleButton.accessibilityLabel = item.isEnabled ? "Disable \(item.type.singularTitle)" : "Enable \(item.type.singularTitle)"
        quickToggleButton.accessibilityHint = item.isEnabled ? "Disable this automation" : "Enable this automation"
        quickToggleButton.accessibilityTraits = .button
        
        // Status indicators accessibility (for VoiceOver users who navigate elements)
        enabledIndicator.isAccessibilityElement = true
        enabledIndicator.accessibilityLabel = "Status: \(item.isEnabled ? "Enabled" : "Disabled")"
        
        if !activeIndicator.isHidden {
            activeIndicator.isAccessibilityElement = true
            activeIndicator.accessibilityLabel = "Currently \(item.isActive ? "Active" : "Inactive")"
        }
    }
    
    // MARK: - Actions
    
    @objc private func quickToggleButtonTapped() {
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Provide visual feedback
        UIView.animate(withDuration: 0.1, animations: {
            self.quickToggleButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.quickToggleButton.transform = .identity
            }
        }
        
        // Notify through notification center
        NotificationCenter.default.post(
            name: .automationItemQuickToggleTapped,
            object: self
        )
    }
}

// MARK: - AutomationSummaryCell

class AutomationSummaryCell: UITableViewCell {
    
    // MARK: - UI Components
    
    private let summaryStackView = UIStackView()
    private let totalLabel = UILabel()
    private let enabledLabel = UILabel()
    private let activeLabel = UILabel()
    private let recentActivityLabel = UILabel()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        selectionStyle = .none
        
        setupSummaryStackView()
        setupLabels()
        setupConstraints()
    }
    
    private func setupSummaryStackView() {
        summaryStackView.axis = .horizontal
        summaryStackView.distribution = .fillEqually
        summaryStackView.spacing = 8
        summaryStackView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(summaryStackView)
    }
    
    private func setupLabels() {
        let labels = [totalLabel, enabledLabel, activeLabel, recentActivityLabel]
        
        for label in labels {
            label.textAlignment = .center
            label.numberOfLines = 2
            label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            
            let containerView = UIView()
            containerView.backgroundColor = UIColor.secondarySystemBackground
            containerView.layer.cornerRadius = 8
            containerView.addSubview(label)
            
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -8)
            ])
            
            summaryStackView.addArrangedSubview(containerView)
        }
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            summaryStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            summaryStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            summaryStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            summaryStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            summaryStackView.heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with items: [AdvancedAutomationViewController.AutomationItem], type: AdvancedAutomationViewController.AutomationType) {
        let total = items.count
        let enabled = items.filter { $0.isEnabled }.count
        let active = items.filter { $0.isActive }.count
        let recentlyUsed = items.filter { 
            guard let lastTriggered = $0.lastTriggered else { return false }
            return lastTriggered.timeIntervalSinceNow > -86400 // Last 24 hours
        }.count
        
        totalLabel.text = "\(total)\nTotal"
        totalLabel.textColor = .label
        
        enabledLabel.text = "\(enabled)\nEnabled"
        enabledLabel.textColor = enabled > 0 ? .systemGreen : .secondaryLabel
        
        activeLabel.text = "\(active)\nActive"
        activeLabel.textColor = active > 0 ? .systemOrange : .secondaryLabel
        
        recentActivityLabel.text = "\(recentlyUsed)\nRecent"
        recentActivityLabel.textColor = recentlyUsed > 0 ? .systemBlue : .secondaryLabel
        
        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = """
        \(type.title) Overview: \(total) total, \(enabled) enabled, \(active) active, \(recentlyUsed) used in last 24 hours
        """
        accessibilityTraits = .staticText
    }
}

// MARK: - Date Extension

extension Date {
    var timeAgoDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: self, relativeTo: Date())
    }
} 