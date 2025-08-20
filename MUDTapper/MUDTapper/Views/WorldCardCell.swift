import UIKit
import CoreData

class WorldCardCell: UICollectionViewCell {
    
    // MARK: - UI Components
    
    private let cardView = UIView()
    private let worldNameLabel = UILabel()
    private let hostnameLabel = UILabel()
    private let statusStackView = UIStackView()
    private let connectionIndicator = UIView()
    private let favoriteButton = UIButton()
    private let quickConnectButton = UIButton()
    private let lastConnectedLabel = UILabel()
    private let automationBadge = UILabel()
    
    private var world: World?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        setupCardView()
        setupLabels()
        setupStatusIndicators()
        setupButtons()
        setupConstraints()
    }
    
    private func setupCardView() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cardView.layer.cornerRadius = 12
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.2).cgColor
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
        cardView.layer.shadowRadius = 4
        cardView.layer.shadowOpacity = 0.1
        
        contentView.addSubview(cardView)
    }
    
    private func setupLabels() {
        // World name
        worldNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        worldNameLabel.textColor = ThemeManager.shared.terminalTextColor
        worldNameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Hostname
        hostnameLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        hostnameLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        hostnameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Last connected
        lastConnectedLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        lastConnectedLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.5)
        lastConnectedLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Automation badge
        automationBadge.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        automationBadge.textColor = ThemeManager.shared.linkColor
        automationBadge.backgroundColor = ThemeManager.shared.linkColor.withAlphaComponent(0.1)
        automationBadge.layer.cornerRadius = 8
        automationBadge.textAlignment = .center
        automationBadge.translatesAutoresizingMaskIntoConstraints = false
        automationBadge.isHidden = true
        
        cardView.addSubview(worldNameLabel)
        cardView.addSubview(hostnameLabel)
        cardView.addSubview(lastConnectedLabel)
        cardView.addSubview(automationBadge)
    }
    
    private func setupStatusIndicators() {
        // Connection indicator
        connectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        connectionIndicator.layer.cornerRadius = 6
        connectionIndicator.backgroundColor = .systemRed
        
        // Status stack view
        statusStackView.axis = .horizontal
        statusStackView.spacing = 8
        statusStackView.alignment = .center
        statusStackView.translatesAutoresizingMaskIntoConstraints = false
        statusStackView.addArrangedSubview(connectionIndicator)
        
        cardView.addSubview(statusStackView)
    }
    
    private func setupButtons() {
        // Favorite button
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.tintColor = ThemeManager.shared.linkColor
        favoriteButton.addTarget(self, action: #selector(favoriteButtonTapped), for: .touchUpInside)
        
        // Quick connect button
        quickConnectButton.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = "Connect"
            config.baseBackgroundColor = ThemeManager.shared.linkColor.withAlphaComponent(0.1)
            config.baseForegroundColor = ThemeManager.shared.linkColor
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            config.cornerStyle = .medium
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 12, weight: .medium)
                return outgoing
            }
            quickConnectButton.configuration = config
        } else {
            quickConnectButton.setTitle("Connect", for: .normal)
            quickConnectButton.setTitleColor(ThemeManager.shared.linkColor, for: .normal)
            quickConnectButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            quickConnectButton.backgroundColor = ThemeManager.shared.linkColor.withAlphaComponent(0.1)
            quickConnectButton.layer.cornerRadius = 8
            quickConnectButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        }
        quickConnectButton.addTarget(self, action: #selector(quickConnectButtonTapped), for: .touchUpInside)
        
        cardView.addSubview(favoriteButton)
        cardView.addSubview(quickConnectButton)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Card view
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            // World name
            worldNameLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            worldNameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            worldNameLabel.trailingAnchor.constraint(lessThanOrEqualTo: favoriteButton.leadingAnchor, constant: -8),
            
            // Favorite button
            favoriteButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            favoriteButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            favoriteButton.widthAnchor.constraint(equalToConstant: 24),
            favoriteButton.heightAnchor.constraint(equalToConstant: 24),
            
            // Hostname
            hostnameLabel.topAnchor.constraint(equalTo: worldNameLabel.bottomAnchor, constant: 4),
            hostnameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            hostnameLabel.trailingAnchor.constraint(lessThanOrEqualTo: quickConnectButton.leadingAnchor, constant: -8),
            
            // Status stack view
            statusStackView.topAnchor.constraint(equalTo: hostnameLabel.bottomAnchor, constant: 8),
            statusStackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            
            // Connection indicator
            connectionIndicator.widthAnchor.constraint(equalToConstant: 12),
            connectionIndicator.heightAnchor.constraint(equalToConstant: 12),
            
            // Last connected
            lastConnectedLabel.topAnchor.constraint(equalTo: statusStackView.bottomAnchor, constant: 8),
            lastConnectedLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            lastConnectedLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -16),
            lastConnectedLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            
            // Automation badge
            automationBadge.topAnchor.constraint(equalTo: statusStackView.topAnchor),
            automationBadge.leadingAnchor.constraint(equalTo: statusStackView.trailingAnchor, constant: 8),
            automationBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            automationBadge.heightAnchor.constraint(equalToConstant: 16),
            
            // Quick connect button
            quickConnectButton.centerYAnchor.constraint(equalTo: hostnameLabel.centerYAnchor),
            quickConnectButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            quickConnectButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with world: World, isConnected: Bool) {
        self.world = world
        
        worldNameLabel.text = world.name ?? "Unknown World"
        hostnameLabel.text = "\(world.hostname ?? ""):\(world.port)"
        
        // Connection status
        connectionIndicator.backgroundColor = isConnected ? ThemeManager.shared.linkColor : ThemeManager.shared.terminalTextColor.withAlphaComponent(0.3)
        
        // Favorite status
        let favoriteImage = world.isFavorite ? UIImage(systemName: "heart.fill") : UIImage(systemName: "heart")
        favoriteButton.setImage(favoriteImage, for: .normal)
        
        // Quick connect button
        quickConnectButton.setTitle(isConnected ? "Switch" : "Connect", for: .normal)
        quickConnectButton.backgroundColor = isConnected ? 
            ThemeManager.shared.terminalTextColor.withAlphaComponent(0.1) : 
            ThemeManager.shared.linkColor.withAlphaComponent(0.1)
        quickConnectButton.setTitleColor(isConnected ? ThemeManager.shared.terminalTextColor : ThemeManager.shared.linkColor, for: .normal)
        
        // Last connected
        if let lastConnected = world.lastModified {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            lastConnectedLabel.text = "Last: \(formatter.localizedString(for: lastConnected, relativeTo: Date()))"
        } else {
            lastConnectedLabel.text = "Never connected"
        }
        
        // Automation count
        let automationCount = getAutomationCount(for: world)
        if automationCount > 0 {
            automationBadge.text = "\(automationCount)"
            automationBadge.isHidden = false
        } else {
            automationBadge.isHidden = true
        }
        
        // Update card appearance for connection state
        cardView.layer.borderColor = isConnected ? 
            ThemeManager.shared.linkColor.withAlphaComponent(0.3).cgColor : 
            ThemeManager.shared.terminalTextColor.withAlphaComponent(0.2).cgColor
    }
    
    private func getAutomationCount(for world: World) -> Int {
        let triggers = Array(world.triggers ?? []).filter { !$0.isHidden }.count
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.count
        let gags = Array(world.gags ?? []).filter { !$0.isHidden }.count
        let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }.count
        return triggers + aliases + gags + tickers
    }
    
    // MARK: - Actions
    
    @objc private func favoriteButtonTapped() {
        guard let world = world else { return }
        
        // Toggle favorite status
        world.isFavorite.toggle()
        
        do {
            try world.managedObjectContext?.save()
            
            // Update UI
            let favoriteImage = world.isFavorite ? UIImage(systemName: "heart.fill") : UIImage(systemName: "heart")
            favoriteButton.setImage(favoriteImage, for: .normal)
            
            // Animate the favorite action
            UIView.animate(withDuration: 0.2, delay: 0, options: [.autoreverse], animations: {
                self.favoriteButton.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            }) { _ in
                self.favoriteButton.transform = .identity
            }
            
        } catch {
            print("Error updating favorite status: \(error)")
        }
    }
    
    @objc private func quickConnectButtonTapped() {
        guard let world = world else { return }
        
        // This would trigger the connection action
        // For now, just provide visual feedback
        UIView.animate(withDuration: 0.1, delay: 0, options: [.autoreverse], animations: {
            self.quickConnectButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            self.quickConnectButton.transform = .identity
        }
        
        // Notify parent controller through delegation or notifications
        NotificationCenter.default.post(
            name: Notification.Name("WorldQuickConnectTapped"),
            object: world
        )
    }
    
    // MARK: - Highlight Effect
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.cardView.transform = self.isHighlighted ? 
                    CGAffineTransform(scaleX: 0.98, y: 0.98) : 
                    .identity
                self.cardView.alpha = self.isHighlighted ? 0.8 : 1.0
            }
        }
    }
}

// MARK: - AddWorldCell

class AddWorldCell: UICollectionViewCell {
    
    private let cardView = UIView()
    private let addIconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cardView.layer.cornerRadius = 12
        cardView.layer.borderWidth = 2
        cardView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        cardView.layer.masksToBounds = true
        
        addIconImageView.translatesAutoresizingMaskIntoConstraints = false
        addIconImageView.image = UIImage(systemName: "plus.circle.fill")
        addIconImageView.tintColor = ThemeManager.shared.linkColor
        addIconImageView.contentMode = .scaleAspectFit
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Add New World"
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = ThemeManager.shared.terminalTextColor
        titleLabel.textAlignment = .center
        
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Create a new MUD connection"
        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        subtitleLabel.textAlignment = .center
        
        contentView.addSubview(cardView)
        cardView.addSubview(addIconImageView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            addIconImageView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            addIconImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            addIconImageView.widthAnchor.constraint(equalToConstant: 32),
            addIconImageView.heightAnchor.constraint(equalToConstant: 32),
            
            titleLabel.topAnchor.constraint(equalTo: addIconImageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -20)
        ])
    }
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.cardView.transform = self.isHighlighted ? 
                    CGAffineTransform(scaleX: 0.95, y: 0.95) : 
                    .identity
                self.cardView.backgroundColor = self.isHighlighted ? 
                    ThemeManager.shared.linkColor.withAlphaComponent(0.1) : 
                    ThemeManager.shared.terminalBackgroundColor
            }
        }
    }
}

// MARK: - WorldSectionHeader

class WorldSectionHeader: UICollectionReusableView {
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separatorView = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = ThemeManager.shared.terminalTextColor
        
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.2)
        
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(separatorView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }
    
    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
} 