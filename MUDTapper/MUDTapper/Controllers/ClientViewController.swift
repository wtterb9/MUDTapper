import UIKit
import CoreData
import AudioToolbox

// MARK: - Helper Classes for Export

class ExportedFileActivityItem: NSObject, UIActivityItemSource {
    private let data: Data
    private let fileName: String
    
    init(data: Data, fileName: String) {
        self.data = data
        self.fileName = fileName
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return fileName
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "public.json"
    }
}

extension DateFormatter {
    static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

class ClientViewController: UIViewController, MudViewDelegate, WorldEditControllerDelegate {
    
    // MARK: - Properties
    
    weak var delegate: ClientViewControllerDelegate?
    
    private var worldObjectID: NSManagedObjectID?
    private var currentWorld: World?
    private var mudSocket: MUDSocket?
    private var ansiProcessor: ANSIProcessor
    internal var sessionLogger: SessionLogger = SessionLogger()
    
    var hostname: String?
    var port: Int32 = 23
    
    var isConnected: Bool {
        return mudSocket?.isConnected ?? false
    }
    
    var currentWorldDescription: String {
        return currentWorld?.worldDescription ?? "No World Selected"
    }
    
    var worldID: NSManagedObjectID? {
        return worldObjectID
    }
    
    var selectedTriggerType: Trigger.TriggerType = .substring
    var selectedOptions: Set<Trigger.TriggerOption> = [.enabled, .ignoreCase]
    
    // Persistent menu tracking
    private var currentPersistentMenu: UIAlertController?
    private var persistentMenuType: PersistentMenuType = .none
    
    enum PersistentMenuType {
        case none
        case radialControls
        case aliases
        case triggers
    }
    
    private var themeManager: ThemeManager
    
    // MARK: - UI Components
    
    private var mudView: MudView!
    private var inputToolbar: InputToolbar!
    private var navigationToolbar: UIToolbar!
    private var noWorldView: UIView!
    
    // Keyboard handling constraints
    private var inputToolbarBottomConstraint: NSLayoutConstraint!
    private var keyboardManager: KeyboardManager?
    

    
    // MARK: - Creation Methods
    
    init(themeManager: ThemeManager? = nil) {
        self.themeManager = themeManager ?? ThemeManager()
        self.ansiProcessor = ANSIProcessor(themeManager: self.themeManager)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        self.themeManager = ThemeManager()
        self.ansiProcessor = ANSIProcessor(themeManager: self.themeManager)
        super.init(coder: coder)
    }
    
    static func client() -> ClientViewController {
        return ClientViewController()
    }
    
    static func client(with worldID: NSManagedObjectID) -> ClientViewController {
        let client = ClientViewController()
        client.worldObjectID = worldID
        
        // Validate the world ID immediately but don't load yet
        let context = PersistenceController.shared.viewContext
        
        if let world = try? context.existingObject(with: worldID) as? World {
            if !world.isDeleted && !world.isHidden {
                // Client created for world
            } else {
                client.worldObjectID = nil
            }
        } else {
            client.worldObjectID = nil
        }
        
        return client
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNotifications()
        
        // Force a clean layout to remove any leftover constraints
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        if worldObjectID != nil {
            loadWorld()
        } else {
            showNoWorldView()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        applyTheme()
    }
    
    deinit {
        // Clean up timers and observers
        stopAllTickers()
        NotificationCenter.default.removeObserver(self)
        
        // Disconnect if still connected
        if isConnected {
            disconnect()
        }
    }
    
    // MARK: - Persistent Menu Management
    
    private func showPersistentMenu(_ alert: UIAlertController, type: PersistentMenuType) {
        // Dismiss any existing persistent menu
        dismissCurrentPersistentMenu()
        
        // Set up the new persistent menu
        currentPersistentMenu = alert
        persistentMenuType = type
        
        // Add a "Done" button to close the persistent menu
        alert.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self] _ in
            self?.dismissCurrentPersistentMenu()
        })
        
        present(alert, animated: true)
    }
    
    private func presentModalThenReturnToPersistent(_ modalAlert: UIAlertController) {
        // Present the modal alert
        present(modalAlert, animated: true)
    }
    
    private func showAlertThenReturnToPersistent(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            // Return to the persistent menu after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refreshCurrentPersistentMenu()
            }
        })
        present(alert, animated: true)
    }
    
    private func dismissCurrentPersistentMenu() {
        currentPersistentMenu?.dismiss(animated: true) {
            self.currentPersistentMenu = nil
            self.persistentMenuType = .none
        }
    }
    
    private func refreshCurrentPersistentMenu() {
        guard currentPersistentMenu != nil, persistentMenuType != .none else { return }
        
        // Dismiss and recreate the menu based on type
        dismissCurrentPersistentMenu()
        
        switch persistentMenuType {
        case .radialControls:
            showPersistentRadialControlMenu()
        case .aliases:
            if let world = currentWorld {
                showPersistentAliasesMenu(world: world)
            }
        case .triggers:
            if let world = currentWorld {
                showPersistentTriggerMenu(world: world)
            }
        case .none:
            break
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = themeManager.terminalBackgroundColor
        
        // Setup navigation toolbar
        setupNavigationToolbar()
        
        // Setup MUD view (terminal display)
        setupMudView()
        
        // Setup input toolbar
        setupInputToolbar()
        
        // Setup no world view
        setupNoWorldView()
        
        // Layout constraints
        setupConstraints()
        
        // Setup keyboard handling
        setupKeyboardHandling()
        

    }
    
    private func setupNavigationToolbar() {
        navigationToolbar = UIToolbar()
        navigationToolbar.translatesAutoresizingMaskIntoConstraints = false
        
        // Set a temporary empty items array to establish proper sizing
        navigationToolbar.items = []
        
        // Add to view first, then update with actual items
        view.addSubview(navigationToolbar)
        
        // Perform layout to establish toolbar sizing before setting real items
        DispatchQueue.main.async {
            self.updateNavigationToolbar()
        }
    }
    
    private func updateNavigationToolbar() {
        let worldButton = UIBarButtonItem(
            title: currentWorldDescription,
            style: .plain,
            target: self,
            action: #selector(worldButtonTapped)
        )
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        let connectButton = UIBarButtonItem(
            title: isConnected ? "Disconnect" : "Connect",
            style: .plain,
            target: self,
            action: #selector(connectButtonTapped)
        )
        
        // Latency display (per-session, colored by threshold)
        let latencyText = latencyDisplayText()
        let latencyItem = UIBarButtonItem(title: latencyText, style: .plain, target: nil, action: nil)
        let latencyFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        latencyItem.setTitleTextAttributes([
            .foregroundColor: latencyDisplayColor(),
            .font: latencyFont
        ], for: .normal)

        // Active-session vitals (HP/Mana) next to latency
        var vitalsItem: UIBarButtonItem?
        if let worldID = worldObjectID, let vitals = SessionVitalsStore.shared.vitals(for: worldID) {
            let now = Date()
            let stale = now.timeIntervalSince(vitals.updatedAt) > 10
            let hpPct = vitals.hpPercent
            let manaPct = vitals.manaPercent
            if hpPct != nil || manaPct != nil {
                let label = UILabel()
                label.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                func colorForHP(_ p: Double?) -> UIColor {
                    guard let p = p else { return .secondaryLabel }
                    let green = Double((UserDefaults.standard.string(forKey: "Vitals.HP.GreenThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(Int.init) ?? 60) / 100.0
                    let yellow = Double((UserDefaults.standard.string(forKey: "Vitals.HP.YellowThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(Int.init) ?? 30) / 100.0
                    if p >= green { return .systemGreen }
                    if p >= yellow { return .systemYellow }
                    return .systemRed
                }
                let hpInt = hpPct.map { Int(round($0 * 100)) }
                let mnInt = manaPct.map { Int(round($0 * 100)) }
                let hpText = hpInt.map { "\($0)%" } ?? "–%"
                let mnText = mnInt.map { "\($0)%" } ?? "–%"
                let baseColorHP = colorForHP(hpPct)
                // Mana: blue by default; if thresholds configured, colorize similarly
                let mnGreenOpt = UserDefaults.standard.string(forKey: "Vitals.Mana.GreenThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let mnYellowOpt = UserDefaults.standard.string(forKey: "Vitals.Mana.YellowThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasMnThresholds = (Int(mnGreenOpt ?? "") != nil) && (Int(mnYellowOpt ?? "") != nil)
                let baseColorMN: UIColor = {
                    guard hasMnThresholds, let p = manaPct else { return .systemBlue }
                    let green = Double(Int(mnGreenOpt!) ?? 60) / 100.0
                    let yellow = Double(Int(mnYellowOpt!) ?? 30) / 100.0
                    if p >= green { return .systemGreen }
                    if p >= yellow { return .systemYellow }
                    return .systemRed
                }()
                let hpColor = stale ? baseColorHP.withAlphaComponent(0.4) : baseColorHP
                let mnColor = stale ? baseColorMN.withAlphaComponent(0.4) : baseColorMN
                let combined = NSMutableAttributedString(string: "HP ")
                combined.append(NSAttributedString(string: hpText, attributes: [.foregroundColor: hpColor]))
                combined.append(NSAttributedString(string: "  MN "))
                combined.append(NSAttributedString(string: mnText, attributes: [.foregroundColor: mnColor]))
                label.attributedText = combined
                vitalsItem = UIBarButtonItem(customView: label)
            }
        }

        // Always show settings button
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            style: .plain,
            target: self,
            action: #selector(settingsButtonTapped)
        )
        
        if let vItem = vitalsItem {
            navigationToolbar.items = [worldButton, flexSpace, connectButton, vItem, latencyItem, settingsButton]
        } else {
            navigationToolbar.items = [worldButton, flexSpace, connectButton, latencyItem, settingsButton]
        }
    }

    private func latencyDisplayText() -> String {
        let ms = mudSocket?.lastLatencyMs ?? 0
        return ms > 0 ? "\(ms) ms" : "– ms"
    }
    
    private func latencyDisplayColor() -> UIColor {
        let ms = mudSocket?.lastLatencyMs ?? 0
        if ms == 0 { return .secondaryLabel }
        if ms <= 150 { return .systemGreen }
        if ms <= 300 { return .systemYellow }
        return .systemRed
    }
    
    private func setupMudView() {
        mudView = MudView(themeManager: themeManager)
        mudView.delegate = self
        mudView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mudView)
    }
    
    private func setupInputToolbar() {
        inputToolbar = InputToolbar(themeManager: themeManager)
        inputToolbar.translatesAutoresizingMaskIntoConstraints = false
        inputToolbar.delegate = self
        view.addSubview(inputToolbar)
    }
    
    private func setupNoWorldView() {
        noWorldView = UIView()
        noWorldView.translatesAutoresizingMaskIntoConstraints = false
        noWorldView.backgroundColor = themeManager.terminalBackgroundColor
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "MUDTapper"
        titleLabel.font = UIFont(name: themeManager.terminalFont.fontName, size: 24) ?? UIFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = themeManager.terminalTextColor
        titleLabel.textAlignment = .center
        noWorldView.addSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "No world selected"
        subtitleLabel.font = themeManager.terminalFont
        subtitleLabel.textColor = themeManager.terminalTextColor.withAlphaComponent(0.7)
        subtitleLabel.textAlignment = .center
        noWorldView.addSubview(subtitleLabel)
        
        let instructionLabel = UILabel()
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.text = "Tap 'No World Selected' above to choose a world\nor swipe from the left edge to open the world list"
        instructionLabel.font = UIFont(name: themeManager.terminalFont.fontName, size: 12) ?? UIFont.systemFont(ofSize: 12)
        instructionLabel.textColor = themeManager.linkColor
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        noWorldView.addSubview(instructionLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: noWorldView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: noWorldView.centerYAnchor, constant: -40),
            
            subtitleLabel.centerXAnchor.constraint(equalTo: noWorldView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            
            instructionLabel.centerXAnchor.constraint(equalTo: noWorldView.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: noWorldView.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: noWorldView.trailingAnchor, constant: -20)
        ])
        
        view.addSubview(noWorldView)
    }
    
    private func setupConstraints() {
        // Create and store the input toolbar bottom constraint
        inputToolbarBottomConstraint = inputToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([
            // Navigation toolbar
            navigationToolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // Input toolbar
            inputToolbarBottomConstraint,
            inputToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            // MUD view
            mudView.topAnchor.constraint(equalTo: navigationToolbar.bottomAnchor),
            mudView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mudView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mudView.bottomAnchor.constraint(equalTo: inputToolbar.topAnchor),
            
            // No world view
            noWorldView.topAnchor.constraint(equalTo: navigationToolbar.bottomAnchor),
            noWorldView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            noWorldView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            noWorldView.bottomAnchor.constraint(equalTo: inputToolbar.topAnchor)
        ])
    }
    
    private func setupNotifications() {
        // Only listen to global theme changes if this session is using the global ThemeManager
        // Per-session ThemeManager instances should not respond to global theme changes
        if themeManager === ThemeManager.shared {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(themeChanged),
                name: .themeDidChange,
                object: nil
            )
        }
        
        // Radial button commands
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRadialButtonCommand(_:)),
            name: NSNotification.Name("RadialButtonCommand"),
            object: nil
        )
        
        // Trigger commands observer will be set up dynamically when world is loaded
        
        // Status bar style updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusBarStyleShouldUpdate(_:)),
            name: .statusBarStyleShouldUpdate,
            object: nil
        )
        
        // Dynamic Type changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )

        // Vitals updates (MSDP/GMCP)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVitalsUpdate(_:)),
            name: .vitalsDidUpdate,
            object: nil
        )
    }

    @objc private func handleVitalsUpdate(_ note: Notification) {
        guard let id = note.object as? NSManagedObjectID else { return }
        if id == worldObjectID {
            DispatchQueue.main.async { self.updateNavigationToolbar() }
        }
    }
    
    private func setupKeyboardHandling() {
        keyboardManager = KeyboardManager(
            willShow: { [weak self] keyboardFrame, duration, curve in
                guard let self = self else { return }
                // Calculate the keyboard position in the view's coordinate system
                let keyboardTop = self.view.convert(keyboardFrame, from: nil).minY
                let tabBarHeight: CGFloat = LayoutConstants.tabBarHeight
                
                // Deactivate the current bottom constraint
                self.inputToolbarBottomConstraint.isActive = false
                
                // Create and activate new constraint positioning the input toolbar above the tab bar
                self.inputToolbarBottomConstraint = self.inputToolbar.bottomAnchor.constraint(equalTo: self.view.topAnchor, constant: keyboardTop - tabBarHeight)
                self.inputToolbarBottomConstraint.isActive = true
                
                UIView.animate(withDuration: min(duration, AnimationConstants.keyboardMaxDuration), delay: 0, options: [UIView.AnimationOptions(rawValue: curve), .allowUserInteraction]) {
                    self.view.layoutIfNeeded()
                }
                
                // Show the number/punctuation bar
                self.inputToolbar.showNumberBar()
                
                // Scroll to the bottom of the MUD view
                self.mudView.scrollToBottom()
            },
            willHide: { [weak self] duration, curve in
                guard let self = self else { return }
                
                // Deactivate the current bottom constraint
                self.inputToolbarBottomConstraint.isActive = false
                
                // Create and activate a new constraint that positions the input toolbar at the bottom of the view
                self.inputToolbarBottomConstraint = self.inputToolbar.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
                self.inputToolbarBottomConstraint.isActive = true
                
                UIView.animate(withDuration: min(duration, AnimationConstants.keyboardMaxDuration), delay: 0, options: [UIView.AnimationOptions(rawValue: curve), .allowUserInteraction]) {
                    self.view.layoutIfNeeded()
                }
                
                // Hide the number/punctuation bar
                self.inputToolbar.hideNumberBar()
            }
        )
    }
    
    // keyboardWillShow/Hide handled by KeyboardManager
    
    // MARK: - Number/Punctuation Bar
    
    
    
    // MARK: - Text Input Support
    
    func insertText(_ text: String) {
        inputToolbar?.insertText(text)
    }
    
    // MARK: - World Management
    
    private func loadWorld() {
        guard let worldID = worldObjectID else { 
            showNoWorldView()
            return 
        }
        
        let context = PersistenceController.shared.viewContext
        
        // Safely load the world object
        guard let world = try? context.existingObject(with: worldID) as? World else {
            showNoWorldView()
            return
        }
        
        // Check if world is valid and not hidden
        if world.isDeleted || world.isHidden {
            showNoWorldView()
            return
        }
        
        currentWorld = world
        hostname = currentWorld?.hostname
        port = currentWorld?.port ?? 23
        
        // Update trigger notification observer for the new world
        updateTriggerNotificationObserver()
        
        showMudView()
        // Ensure socket knows which world to attribute MSDP/GMCP vitals to
        if let world = currentWorld {
            mudSocket?.currentWorldObjectID = world.objectID
        }
        updateUI()
    }
    
    private func showNoWorldView() {
        noWorldView.isHidden = false
        mudView.isHidden = true
        inputToolbar.isHidden = true
        
        // Update connect button state
        if let connectButton = navigationToolbar.items?.last {
            connectButton.isEnabled = false
        }
    }
    
    private func showMudView() {
        noWorldView.isHidden = true
        mudView.isHidden = false
        inputToolbar.isHidden = false
        
        // Update connect button state
        if let connectButton = navigationToolbar.items?.last {
            connectButton.isEnabled = true
        }
    }
    
    func updateCurrentWorld(_ newWorldID: NSManagedObjectID, connectAfterUpdate: Bool = false) {
        worldObjectID = newWorldID
        loadWorld()
        
        if connectAfterUpdate {
            connect()
        }
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard let hostname = hostname, !hostname.isEmpty, port > 0 else {
            showAlert(title: "Connection Error", message: "Invalid hostname or port")
            return
        }
        
        // Disconnect if already connected
        if isConnected {
            disconnect()
        }
        
        // Create new socket
        mudSocket = MUDSocket()
        mudSocket?.delegate = self
        // Propagate world ID for MSDP vitals attribution
        if let world = currentWorld {
            mudSocket?.currentWorldObjectID = world.objectID
        }
        
        do {
            try mudSocket?.connect(to: hostname, port: UInt16(port))
            mudView.appendTextWithColor("Connecting to \(hostname):\(port)...\n", color: themeManager.linkColor)
            
            // Start session logging if we have a world
            if let world = currentWorld {
                sessionLogger.startLogging(for: world)
            }
            
            // Start background audio for background protection
            SilentAudioManager.shared.startBackgroundAudio()
        } catch {
            showAlert(title: "Connection Error", message: error.localizedDescription)
        }
        
        // Update UI
        updateConnectionStatus()
    }
    
    func disconnect() {
        mudSocket?.disconnect()
        mudSocket = nil
        
        // Stop session logging
        sessionLogger.stopLogging()
        
        // Stop all tickers when disconnecting
        stopAllTickers()
        
        mudView.appendTextWithColor("Disconnected.\n", color: themeManager.linkColor)
        
        // Stop background audio when disconnected
        SilentAudioManager.shared.stopBackgroundAudio()
        
        // Update UI
        updateConnectionStatus()
        
        // Notify delegate
        delegate?.clientDidDisconnect(self)
    }
    
    // MARK: - UI Updates
    
    private func updateUI() {
        // Update navigation toolbar
        updateNavigationToolbar()
    }
    
    private func updateConnectionStatus() {
        updateNavigationToolbar()
    }
    
    private func applyTheme() {
        view.backgroundColor = themeManager.terminalBackgroundColor
        navigationToolbar.barTintColor = themeManager.terminalBackgroundColor
        navigationToolbar.tintColor = themeManager.linkColor
        
        noWorldView?.backgroundColor = themeManager.terminalBackgroundColor
        mudView?.applyTheme()
        inputToolbar?.applyTheme()
    }
    
    // MARK: - Actions
    
    @objc private func worldButtonTapped() {
        delegate?.clientDidRequestWorldSelection(self)
    }
    
    @objc private func connectButtonTapped() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }
    
    @objc private func themeChanged() {
        // Only apply theme changes if this session is using the global ThemeManager
        // Per-session ThemeManager instances should not respond to global theme changes
        if themeManager === ThemeManager.shared {
            DispatchQueue.main.async {
                self.applyTheme()
            }
        }
    }
    
    @objc private func statusBarStyleShouldUpdate(_ notification: Notification) {
        DispatchQueue.main.async {
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 13.0, *) {
            return themeManager.isDarkTheme ? .lightContent : .darkContent
        } else {
            return themeManager.isDarkTheme ? .lightContent : .default
        }
    }
    
    @objc private func contentSizeCategoryDidChange() {
        DispatchQueue.main.async {
            self.applyTheme()
        }
    }
    
    @objc private func dismissKeyboard() {
        _ = inputToolbar?.resignFirstResponder()
    }
    
    @objc private func settingsButtonTapped() {
        presentFullScreenSettings()
    }
    
    private func presentFullScreenSettings() {
        let hub = SettingsHubViewController(world: currentWorld)
        hub.onDismiss = { [weak self] in
            self?.refreshCurrentPersistentMenu()
        }
        let nav = UINavigationController(rootViewController: hub)
        nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        present(nav, animated: true)
    }
    
    // Legacy entry points below will remain for now but are unused; full-screen hub replaces them.
    
    // MARK: - New Categorized Settings Menus
    
    private func getAutomationItemCount(world: World) -> Int {
        let triggers = Array(world.triggers ?? []).filter { !$0.isHidden }.count
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.count
        let gags = Array(world.gags ?? []).filter { !$0.isHidden }.count
        let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }.count
        return triggers + aliases + gags + tickers
    }
    
    private func showWorldConfigurationMenu(world: World) {
        let alert = UIAlertController(title: "🌍 World Configuration", message: "Manage world settings and connection", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📝 Edit World Info", style: .default) { [weak self] _ in
            self?.showWorldInfo(world: world)
        })
        
        alert.addAction(UIAlertAction(title: "⚙️ World Settings", style: .default) { [weak self] _ in
            self?.showWorldSettings(world: world)
        })
        
        alert.addAction(UIAlertAction(title: "🔧 Connection Settings", style: .default) { [weak self] _ in
            self?.showConnectionSettings(world: world)
        })
        
        alert.addAction(UIAlertAction(title: "🧬 Clone World", style: .default) { _ in
            world.deepClone {
                // Do not auto-load the new session; just leave it available in the list
                // Optionally show a lightweight confirmation toast/alert
                ErrorPresenter.showError(title: "World Cloned", message: "A full clone has been added to your worlds.")
            }
        })
        
        alert.addAction(UIAlertAction(title: "❓ Help: World Setup", style: .default) { [weak self] _ in
            self?.showWorldSetupHelp()
        })
        
        alert.addAction(UIAlertAction(title: "← Back", style: .cancel) { [weak self] _ in
            self?.presentFullScreenSettings()
        })
        
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showAutomationMenu(world: World) {
        let triggers = Array(world.triggers ?? []).filter { !$0.isHidden }
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }
        let gags = Array(world.gags ?? []).filter { !$0.isHidden }
        let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }
        
        let alert = UIAlertController(title: "Automation", message: "Manage triggers, aliases, gags, and tickers", preferredStyle: .actionSheet)
        
        let triggerTitle = triggers.count > 0 ? "🎯 Triggers (\(triggers.count))" : "🎯 Triggers"
        let triggerAccessibilityLabel = triggers.count > 0 ? "Triggers, \(triggers.count) configured" : "Triggers"
        addAccessibleAction(to: alert, title: triggerTitle, accessibilityLabel: triggerAccessibilityLabel) { [weak self] _ in
            self?.showTriggerMenu(world: world)
        }
        
        let aliasTitle = aliases.count > 0 ? "📋 Aliases (\(aliases.count))" : "📋 Aliases"
        let aliasAccessibilityLabel = aliases.count > 0 ? "Aliases, \(aliases.count) configured" : "Aliases"
        addAccessibleAction(to: alert, title: aliasTitle, accessibilityLabel: aliasAccessibilityLabel) { [weak self] _ in
            self?.showAliasesMenu(world: world)
        }
        
        let gagTitle = gags.count > 0 ? "🚫 Gags (\(gags.count))" : "🚫 Gags"
        let gagAccessibilityLabel = gags.count > 0 ? "Gags, \(gags.count) configured" : "Gags"
        addAccessibleAction(to: alert, title: gagTitle, accessibilityLabel: gagAccessibilityLabel) { [weak self] _ in
            self?.showGagsMenu(world: world)
        }
        
        let tickerTitle = tickers.count > 0 ? "⏰ Tickers (\(tickers.count))" : "⏰ Tickers"
        let tickerAccessibilityLabel = tickers.count > 0 ? "Tickers, \(tickers.count) configured" : "Tickers"
        addAccessibleAction(to: alert, title: tickerTitle, accessibilityLabel: tickerAccessibilityLabel) { [weak self] _ in
            self?.showTickersMenu(world: world)
        }
        
        addAccessibleAction(to: alert, title: "❓ Help: Automation", accessibilityLabel: "Help about Automation features") { [weak self] _ in
            self?.showAutomationHelp()
        }
        
        alert.addAction(UIAlertAction(title: "← Back", style: .cancel) { [weak self] _ in
            self?.presentFullScreenSettings()
        })
        
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showAppearanceMenu() {
        // Route directly to the modern Theme & Appearance settings
        showThemeSettings()
    }
    
    private func showInputControlsMenu() {
        let alert = UIAlertController(title: "⌨️ Input & Controls", message: "Configure input behavior and controls", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📱 Input Settings", style: .default) { [weak self] _ in
            self?.showInputSettings()
        })
        
        alert.addAction(UIAlertAction(title: "🎮 Radial Controls", style: .default) { [weak self] _ in
            self?.showRadialControlSettings()
        })
        
        alert.addAction(UIAlertAction(title: "♿ Accessibility", style: .default) { [weak self] _ in
            self?.showAccessibilitySettings()
        })
        
        alert.addAction(UIAlertAction(title: "❓ Help: Input", style: .default) { [weak self] _ in
            self?.showInputHelp()
        })
        
        alert.addAction(UIAlertAction(title: "← Back", style: .cancel) { [weak self] _ in
            self?.presentFullScreenSettings()
        })
        
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showLoggingDataMenu() {
        let alert = UIAlertController(title: "📁 Logging & Data", message: "Manage session logs and data export", preferredStyle: .actionSheet)
        
        let loggingStatus = sessionLogger.isLogging ? " (Active)" : " (Inactive)"
        alert.addAction(UIAlertAction(title: "📄 Session Logs\(loggingStatus)", style: .default) { [weak self] _ in
            self?.showSessionLogsMenu()
        })
        
        alert.addAction(UIAlertAction(title: "💾 Export Data", style: .default) { [weak self] _ in
            self?.showExportDataMenu()
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Clear Data", style: .destructive) { [weak self] _ in
            self?.showClearDataMenu()
        })
        
        alert.addAction(UIAlertAction(title: "❓ Help: Data Management", style: .default) { [weak self] _ in
            self?.showDataManagementHelp()
        })
        
        alert.addAction(UIAlertAction(title: "← Back", style: .cancel) { [weak self] _ in
            self?.presentFullScreenSettings()
        })
        
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showHelpAboutMenu() {
        let alert = UIAlertController(title: "❓ Help & About", message: "Get help and app information", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📊 Session Dashboard", style: .default) { [weak self] _ in
            self?.showSessionDashboard()
        })
        
        alert.addAction(UIAlertAction(title: "📖 User Guide", style: .default) { [weak self] _ in
            self?.showUserGuide()
        })
        
        alert.addAction(UIAlertAction(title: "❓ Feature Help", style: .default) { [weak self] _ in
            self?.showFeatureHelp()
        })
        
        alert.addAction(UIAlertAction(title: "ℹ️ About MUDTapper", style: .default) { [weak self] _ in
            self?.showAboutApp()
        })
        
        alert.addAction(UIAlertAction(title: "🐛 Report Issue", style: .default) { [weak self] _ in
            self?.showReportIssue()
        })
        
        alert.addAction(UIAlertAction(title: "← Back", style: .cancel) { [weak self] _ in
            self?.presentFullScreenSettings()
        })
        
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showSessionDashboard() {
        let sessionDashboard = SessionDashboardViewController()
        let navController = UINavigationController(rootViewController: sessionDashboard)
        present(navController, animated: true)
    }
    
    // MARK: - Modern Settings (Phase 2 Integration)
    
    private func showModernInputSettings() {
        let inputSettings = InputSettingsViewController(clientViewController: self)
        inputSettings.title = "Input Settings"
        inputSettings.onDismiss = { [weak self] in
            self?.refreshCurrentPersistentMenu()
        }
        let navController = UINavigationController(rootViewController: inputSettings)
        present(navController, animated: true)
    }
    
    private func showModernThemeSettings() {
        let themeSettings = ThemeSettingsViewController()
        themeSettings.title = "Theme Settings"
        themeSettings.onDismiss = { [weak self] in
            self?.refreshCurrentPersistentMenu()
        }
        let navController = UINavigationController(rootViewController: themeSettings)
        present(navController, animated: true)
    }
    
    private func setupAlertForPresentation(_ alert: UIAlertController) {
        // For iPad popover
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
    }
    
    // MARK: - Accessibility Helpers
    
    private func createAccessibleAction(title: String, style: UIAlertAction.Style = .default, accessibilityLabel: String? = nil, handler: ((UIAlertAction) -> Void)? = nil) -> UIAlertAction {
        let action = UIAlertAction(title: title, style: style, handler: handler)
        
        // Set accessibility label if provided, otherwise use the title without emoji
        if let customLabel = accessibilityLabel {
            action.accessibilityLabel = customLabel
        } else {
            // Remove emoji from title for accessibility
            let cleanTitle = title.replacingOccurrences(of: #"[^\p{L}\p{N}\p{P}\p{S}\s]+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            action.accessibilityLabel = cleanTitle.isEmpty ? title : cleanTitle
        }
        
        return action
    }
    
    private func addAccessibleAction(to alert: UIAlertController, title: String, style: UIAlertAction.Style = .default, accessibilityLabel: String? = nil, handler: ((UIAlertAction) -> Void)? = nil) {
        let action = createAccessibleAction(title: title, style: style, accessibilityLabel: accessibilityLabel, handler: handler)
        alert.addAction(action)
    }
    
    // MARK: - Text Management
    
    func clearText() {
        mudView?.clearText()
    }
    
    func hideKeyboard() {
        _ = inputToolbar?.resignFirstResponder()
    }
    
    // Returns true if the input toolbar's text field currently has focus (keyboard visible)
    func isInputFocused() -> Bool {
        return inputToolbar?.inputTextField?.isFirstResponder ?? false
    }
    
    // Brings focus to the input toolbar's text field (shows keyboard)
    func focusInput() {
        _ = inputToolbar?.becomeFirstResponder()
    }
    
    func setNavVisible(_ visible: Bool) {
        navigationToolbar.isHidden = !visible
    }
    
    // MARK: - Command Processing
    
    func processCommand(_ command: String) {
        // Handle test commands early to avoid unnecessary processing
        if command.lowercased().hasPrefix("test") {
            handleTestCommands(command)
            return
        }
        
        // Process and send immediately for better responsiveness
        sendCommandDirectly(command)
        
        // Log after sending to avoid blocking the send operation
        sessionLogger.writeCommand(command)
        
        // Process triggers on a background queue to avoid blocking UI
        if let world = currentWorld {
            DispatchQueue.global(qos: .userInitiated).async {
                world.processTriggersForText(command)
            }
        }
    }
    
    private func handleTestCommands(_ command: String) {
        switch command.lowercased() {
        case "testcolors":
            mudView?.testANSIColors()
        case "test256colors":
            mudView?.testXterm256ColorPalette()
        case "xterm256":
            if isConnected {
                setAwaitingXterm256Response()
                mudSocket?.sendXterm256Colors()
                mudView?.appendTextWithColor("Sent XTERM_256_COLORS=1 via telnet MSDP\n", color: .green)
            } else {
                mudView?.appendTextWithColor("Not connected to server\n", color: .red)
            }
        case "luaxterm256":
            if isConnected {
                setAwaitingXterm256Response()
                mudSocket?.sendMSDP(variable: "XTERM_256_COLORS", value: "1")
                mudView?.appendTextWithColor("Sent MSDP XTERM_256_COLORS=1 via telnet subnegotiation\n", color: .green)
            } else {
                mudView?.appendTextWithColor("Not connected to server\n", color: .red)
            }
        case "checkmsdp":
            if isConnected {
                mudView?.appendTextWithColor("Sending MSDP and monitoring for response...\n", color: .cyan)
                mudView?.appendTextWithColor("Watch for 256-color codes in debug output\n", color: .cyan)
                
                // Send MSDP
                mudSocket?.sendMSDP(variable: "XTERM_256_COLORS", value: "1")
                
                // Wait a moment then send a test command that might trigger colored output
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.mudSocket?.send("look")
                }
                
                mudView?.appendTextWithColor("Sent MSDP + look command\n", color: .green)
            } else {
                mudView?.appendTextWithColor("Not connected to server\n", color: .red)
            }
        default:
            // Unknown test command, process normally
            sendCommandDirectly(command)
        }
    }
    
    private func sendCommandDirectly(_ command: String) {
        // Send to server immediately for best responsiveness
        mudSocket?.send(command)
    }
    
    func sendDirectCommand(_ command: String) {
        // Process aliases for this session before sending
        if let world = currentWorld,
           let aliasCommands = world.commandsForMatchingAlias(input: command) {
            // If this command matches an alias, send the alias commands instead
            for aliasCommand in aliasCommands {
                // Check if the alias command is itself a multi-session command
                if aliasCommand.hasPrefix("#") {
                    // Handle nested multi-session commands from aliases
                    processMultiSessionCommand(aliasCommand)
                } else {
                    // Send the alias command directly (don't process triggers for multi-session commands)
                    mudSocket?.send(aliasCommand)
                    
                    // Show in local echo if enabled
                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.localEcho) {
                        mudView?.appendTextWithColor("> \(aliasCommand) [multi-session alias]\n", 
                                          color: themeManager.linkColor.withAlphaComponent(0.7))
                    }
                }
            }
        } else {
            // No alias match, send command directly without trigger processing
            mudSocket?.send(command)
            
            // Show in local echo if enabled
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.localEcho) {
                mudView?.appendTextWithColor("> \(command) [multi-session]\n", 
                                  color: themeManager.linkColor.withAlphaComponent(0.7))
            }
        }
    }
    
    private func processMultiSessionCommand(_ input: String) {
        // Parse #target command format
        guard let spaceIndex = input.firstIndex(of: " ") else {
            // No command after #target
            showMultiSessionHelp()
            return
        }
        
        let target = String(input[input.index(after: input.startIndex)..<spaceIndex])
        let command = String(input[input.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !command.isEmpty else {
            showMultiSessionHelp()
            return
        }
        
        // Get the ClientContainer to access all sessions
        guard let clientContainer = findClientContainer() else {
            mudView?.appendText("Error: Could not access session manager\n", color: .red)
            return
        }
        
        if target.lowercased() == "all" {
            // Send to all connected sessions
            let sentCount = clientContainer.sendCommandToAllSessions(command)
            mudView?.appendText("Command sent to \(sentCount) session(s): \(command)\n", 
                              color: themeManager.linkColor.withAlphaComponent(0.8))
        } else {
            // Send to specific session by name
            if clientContainer.sendCommandToSession(named: target, command: command) {
                mudView?.appendText("Command sent to '\(target)': \(command)\n", 
                                  color: themeManager.linkColor.withAlphaComponent(0.8))
            } else {
                mudView?.appendText("Session '\(target)' not found or not connected\n", color: .red)
                
                // Show available sessions
                let availableSessions = clientContainer.getAvailableSessionNames()
                if !availableSessions.isEmpty {
                    mudView?.appendText("Available sessions: \(availableSessions.joined(separator: ", "))\n", 
                                      color: themeManager.terminalTextColor.withAlphaComponent(0.7))
                }
            }
        }
    }
    

    
    private func findClientContainer() -> ClientContainer? {
        var parentVC = self.parent
        while parentVC != nil {
            if let clientContainer = parentVC as? ClientContainer {
                return clientContainer
            }
            parentVC = parentVC?.parent
        }
        return ClientContainer.shared
    }
    
    // MARK: - World Settings
    
    private func showWorldSettings(world: World) {
        let worldEditController = WorldEditController(world: world)
        worldEditController.delegate = self
        
        let navController = UINavigationController(rootViewController: worldEditController)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    // MARK: - Session Logs
    
    private func showSessionLogsMenu() {
        let alert = UIAlertController(title: "Session Logs", message: "Manage session logging and view log files", preferredStyle: .actionSheet)
        
        // Auto-logging toggle
        let autoLoggingEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoLogging)
        let autoLoggingTitle = autoLoggingEnabled ? "🟢 Disable Auto-Logging" : "🔴 Enable Auto-Logging"
        alert.addAction(UIAlertAction(title: autoLoggingTitle, style: .default) { _ in
            UserDefaults.standard.set(!autoLoggingEnabled, forKey: UserDefaultsKeys.autoLogging)
            let message = !autoLoggingEnabled ? "Auto-logging enabled for new sessions" : "Auto-logging disabled"
            self.showAlert(title: "Logging Settings", message: message)
        })
        
        // Manual logging toggle (if connected)
        if let world = currentWorld, isConnected {
            if sessionLogger.isLogging {
                alert.addAction(UIAlertAction(title: "⏹️ Stop Current Session Log", style: .default) { _ in
                    self.sessionLogger.stopLogging()
                    self.showAlert(title: "Logging Stopped", message: "Session logging has been stopped")
                })
            } else {
                alert.addAction(UIAlertAction(title: "▶️ Start Session Log", style: .default) { _ in
                    self.sessionLogger.startLogging(for: world, force: true)
                    self.showAlert(title: "Logging Started", message: "Session logging has been started")
                })
            }
        }
        
        // View logs
        alert.addAction(UIAlertAction(title: "📁 View Log Files", style: .default) { _ in
            self.showSessionLogs()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        present(alert, animated: true)
    }
    
    private func showSessionLogs() {
        let logManagerController = LogManagerViewController()
        let navController = UINavigationController(rootViewController: logManagerController)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    // MARK: - WorldEditControllerDelegate
    
    func worldEditController(_ controller: WorldEditController, didSaveWorld world: World) {
        // Refresh the current world reference and UI
        currentWorld = world
        // Update trigger notification observer for the updated world
        updateTriggerNotificationObserver()
        setupForWorld()
        controller.dismiss(animated: true)
    }
    
    private func setupForWorld() {
        // Update UI after world changes
        updateUI()
        
        // Update the world view if needed
        if currentWorld != nil {
            mudView?.isHidden = false
            noWorldView?.isHidden = true
        } else {
            mudView?.isHidden = true
            noWorldView?.isHidden = false
        }
    }
    
    func worldEditControllerDidCancel(_ controller: WorldEditController) {
        controller.dismiss(animated: true)
    }
    
    // MARK: - Utility
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func requestCloseWorld() {
        // Find the parent ClientContainer and request to close this world
        if let clientContainer = parent as? ClientContainer {
            clientContainer.showCloseWorldOptions()
        }
    }
    
    // MARK: - New Helper Methods
    
    private func showConnectionSettings(world: World) {
        // For now, redirect to existing world settings
        showWorldSettings(world: world)
    }
    
    private func showExportDataMenu() {
        let alert = UIAlertController(title: "💾 Export Data", message: "Export your settings and data", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "📤 Export All Settings", style: .default) { [weak self] _ in
            self?.exportAllSettings()
        })
        
        alert.addAction(UIAlertAction(title: "📋 Export World Config", style: .default) { [weak self] _ in
            self?.exportWorldConfig()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showClearDataMenu() {
        let alert = UIAlertController(title: "🗑️ Clear Data", message: "Clear app data and logs", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "🗂️ Clear All Logs", style: .destructive) { [weak self] _ in
            self?.clearAllLogs()
        })
        
        alert.addAction(UIAlertAction(title: "🔄 Reset All Settings", style: .destructive) { [weak self] _ in
            self?.resetAllSettings()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    // MARK: - Help Methods
    
    private func showWorldSetupHelp() {
        showHelpAlert(title: "🌍 World Setup Help", 
                     message: "Configure your MUD world connection:\n\n• World Info: Set name, hostname, and port\n• Connection Settings: Configure auto-connect and login\n• World Settings: Customize behavior for this world")
    }
    
    private func showAutomationHelp() {
        showHelpAlert(title: "🤖 Automation Help", 
                     message: "Automate your MUD experience:\n\n• Triggers: Execute commands when text appears\n• Aliases: Create shortcuts for long commands\n• Gags: Hide unwanted text from display\n• Tickers: Run commands at regular intervals")
    }
    
    private func showThemeHelp() {
        showHelpAlert(title: "🎨 Theme Help", 
                     message: "Customize your visual experience:\n\n• Themes: Choose color schemes\n• Fonts: Adjust text appearance\n• Radial Controls: Position and style on-screen controls\n• Display: Configure layout and behavior")
    }
    
    private func showInputHelp() {
        showHelpAlert(title: "⌨️ Input Help", 
                     message: "Configure input and controls:\n\n• Input Settings: Local echo, autocorrect\n• Network Settings: Connection behavior\n• Accessibility: VoiceOver and dynamic type support")
    }
    
    private func showDataManagementHelp() {
        showHelpAlert(title: "📁 Data Management Help", 
                     message: "Manage your data:\n\n• Session Logs: Record your gameplay\n• Export Data: Backup settings and worlds\n• Clear Data: Remove logs and reset settings")
    }
    
    private func showUserGuide() {
        let alert = UIAlertController(title: "📖 User Guide", message: "Choose a topic to learn about", preferredStyle: .actionSheet)
        
        addAccessibleAction(to: alert, title: "🚀 Getting Started", accessibilityLabel: "Getting Started Guide") { [weak self] _ in
            self?.showGettingStartedGuide()
        }
        
        addAccessibleAction(to: alert, title: "🌍 Managing Worlds", accessibilityLabel: "Managing Worlds Guide") { [weak self] _ in
            self?.showWorldManagementGuide()
        }
        
        addAccessibleAction(to: alert, title: "🤖 Automation Features", accessibilityLabel: "Automation Features Guide") { [weak self] _ in
            self?.showAutomationGuide()
        }
        
        addAccessibleAction(to: alert, title: "📱 Advanced Features", accessibilityLabel: "Advanced Features Guide") { [weak self] _ in
            self?.showAdvancedFeaturesGuide()
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showGettingStartedGuide() {
        showHelpAlert(title: "🚀 Getting Started", 
                     message: "Welcome to MUDTapper!\n\n1. Swipe from left edge or tap 'Add' to open world list\n2. Tap '+' to add a new world with hostname and port\n3. Tap a world name to connect\n4. Type commands in the text field at bottom\n5. Tap ⚙️ for settings and customization")
    }
    
    private func showWorldManagementGuide() {
        showHelpAlert(title: "🌍 Managing Worlds", 
                     message: "World Management:\n\n• Multiple Tabs: Each world gets its own tab\n• Status Indicators: 🟢 = connected, 📝 = logging, 🤖 = automation\n• Quick Actions: Long-press tabs for options\n• Multi-Session: Type '#all command' to send to all sessions\n• Session Names: Use '#worldname command' for specific worlds")
    }
    
    private func showAutomationGuide() {
        showHelpAlert(title: "🤖 Automation Guide", 
                     message: "Powerful Automation:\n\n• Triggers: React to incoming text automatically\n• Aliases: Create command shortcuts with variables\n• Gags: Hide unwanted spam text\n• Tickers: Execute commands at regular intervals\n\nAccess via Settings → Automation")
    }
    
    private func showAdvancedFeaturesGuide() {
        showHelpAlert(title: "📱 Advanced Features", 
                     message: "Advanced Features:\n\n• Custom Themes: Multiple color schemes\n• Radial Controls: Touch-friendly movement\n• Session Logging: Record your gameplay\n• ANSI Colors: Full terminal color support\n• Background Play: Stay connected when app is backgrounded")
    }
    
    private func showFeatureHelp() {
        let alert = UIAlertController(title: "❓ Feature Help", message: "Choose a feature to learn about", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "🎯 Triggers & Pattern Matching", style: .default) { [weak self] _ in
            self?.showTriggerPatternHelp()
        })
        
        alert.addAction(UIAlertAction(title: "📋 Aliases & Variables", style: .default) { [weak self] _ in
            self?.showAliasVariableHelp()
        })
        
        alert.addAction(UIAlertAction(title: "🎮 Radial Controls", style: .default) { [weak self] _ in
            self?.showRadialControlHelp()
        })
        
        alert.addAction(UIAlertAction(title: "📱 Multi-Session Commands", style: .default) { [weak self] _ in
            self?.showMultiSessionHelp()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        setupAlertForPresentation(alert)
        present(alert, animated: true)
    }
    
    private func showAboutApp() {
        showHelpAlert(title: "ℹ️ About MUDTapper", 
                     message: "MUDTapper Swift v2.0\n\nA modern MUD client for iOS with advanced automation features.\n\nSupports ANSI colors, triggers, aliases, multi-session play, and much more.")
    }
    
    private func showReportIssue() {
        showHelpAlert(title: "🐛 Report Issue", 
                     message: "Found a bug or have a suggestion?\n\nPlease report issues through the app's GitHub repository or contact the developer.")
    }
    
    private func showTriggerPatternHelp() {
        showHelpAlert(title: "🎯 Trigger Patterns", 
                     message: "Pattern Types:\n\n• Substring: Matches text anywhere in line\n  Example: 'hungry' matches 'You are hungry'\n\n• Wildcard: Use * and ? for flexible matching\n  Example: '* tells you *' matches any tell\n\n• Regex: Full regular expression support\n  Example: '\\d+ damage' matches '25 damage'\n\n• Exact: Matches entire line exactly\n  Example: Must match line word-for-word")
    }
    
    private func showAliasVariableHelp() {
        showHelpAlert(title: "📋 Alias Variables", 
                     message: "Use variables in aliases:\n\n• $1, $2, $3: Individual words from input\n  If you type 'k orc', then $1=orc\n\n• $*: All remaining text after alias\n  If you type 'gt hello everyone', then $*='hello everyone'\n\n• Example alias 'gt' → 'tell group $*'\n  When you type 'gt hello', it sends 'tell group hello'")
    }
    
    private func showRadialControlHelp() {
        showHelpAlert(title: "🎮 Radial Controls", 
                     message: "On-screen movement controls:\n\n• Tap and drag to move\n• Customize commands for each direction\n• Position on left or right side\n• Multiple visual styles available")
    }
    
    private func showMultiSessionHelp() {
        showHelpAlert(title: "📱 Multi-Session Commands", 
                     message: "Send commands to multiple sessions:\n\n• #all <command>: Send to all connected sessions\n• #worldname <command>: Send to specific world\n• Great for playing multiple characters")
    }
    
    private func showHelpAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it!", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Utility Methods
    
    private func exportAllSettings() {
        // Collect all user defaults
        let userDefaults = UserDefaults.standard.dictionaryRepresentation()
        let settingsData = userDefaults.filter { key, _ in
            // Filter to only include app-specific settings
            key.hasPrefix("com.mudtapperapp.") || key.hasPrefix("MUDTapper")
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settingsData, options: .prettyPrinted)
            let fileName = "MUDTapper_Settings_\(DateFormatter.fileNameDateFormatter.string(from: Date())).json"
            
            let activityVC = UIActivityViewController(activityItems: [
                ExportedFileActivityItem(data: jsonData, fileName: fileName)
            ], applicationActivities: nil)
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            
            present(activityVC, animated: true)
        } catch {
            showAlert(title: "Export Error", message: "Failed to export settings: \(error.localizedDescription)")
        }
    }
    
    private func exportWorldConfig() {
        guard let world = currentWorld else {
            showAlert(title: "No World", message: "No world is currently selected to export.")
            return
        }
        
        // Create export dictionary
        var worldData: [String: Any] = [:]
        worldData["name"] = world.name
        worldData["hostname"] = world.hostname
        worldData["port"] = world.port
        worldData["connectCommand"] = world.connectCommand
        worldData["autoConnect"] = world.autoConnect
        worldData["isFavorite"] = world.isFavorite
        worldData["isSecure"] = world.isSecure
        worldData["username"] = world.username
        // Note: password intentionally excluded for security
        
        // Export triggers
        if let triggers = world.triggers {
            worldData["triggers"] = triggers.map { trigger in
                [
                    "name": trigger.label ?? "",
                    "pattern": trigger.trigger ?? "",
                    "commands": trigger.commands ?? "",
                    "type": trigger.triggerType,
                    "priority": trigger.priority,
                    "group": trigger.group ?? "",
                    "isEnabled": trigger.isEnabled,
                    "options": trigger.options ?? ""
                ]
            }
        }
        
        // Export aliases
        if let aliases = world.aliases {
            worldData["aliases"] = aliases.map { alias in
                [
                    "name": alias.name ?? "",
                    "commands": alias.commands ?? "",
                    "isEnabled": alias.isEnabled
                ]
            }
        }
        
        // Export gags
        if let gags = world.gags {
            worldData["gags"] = gags.map { gag in
                [
                    "pattern": gag.gag ?? "",
                    "type": gag.gagType,
                    "isEnabled": gag.isEnabled
                ]
            }
        }
        
        // Export tickers
        if let tickers = world.tickers {
            worldData["tickers"] = tickers.map { ticker in
                [
                    "commands": ticker.commands ?? "",
                    "interval": ticker.interval,
                    "isEnabled": ticker.isEnabled,
                    "soundFileName": ticker.soundFileName ?? ""
                ]
            }
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: worldData, options: .prettyPrinted)
            let fileName = "MUDTapper_World_\(world.name ?? "Unnamed")_\(DateFormatter.fileNameDateFormatter.string(from: Date())).json"
            
            let activityVC = UIActivityViewController(activityItems: [
                ExportedFileActivityItem(data: jsonData, fileName: fileName)
            ], applicationActivities: nil)
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            }
            
            present(activityVC, animated: true)
        } catch {
            showAlert(title: "Export Error", message: "Failed to export world configuration: \(error.localizedDescription)")
        }
    }
    
    private func clearAllLogs() {
        showAlert(title: "Clear Logs", message: "All logs have been cleared.")
    }
    
    private func resetAllSettings() {
        let alert = UIAlertController(title: "Reset Settings", message: "Are you sure you want to reset all settings to defaults?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
            // Reset user defaults to default values
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
            self.showAlert(title: "Settings Reset", message: "All settings have been reset to defaults. Please restart the app.")
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    // MARK: - Legacy App Settings Methods (for backward compatibility)
    
    private func showAppSettings() {
        let alert = UIAlertController(title: "App Settings", message: "Configure global application settings", preferredStyle: .actionSheet)
        
        // Theme Settings
        alert.addAction(UIAlertAction(title: "Themes", style: .default) { [weak self] _ in
            self?.showThemeSettings()
        })
        
        // Font Settings
        alert.addAction(UIAlertAction(title: "Font Settings", style: .default) { [weak self] _ in
            self?.showFontSettings()
        })
        
        // Input Settings
        alert.addAction(UIAlertAction(title: "Input Settings", style: .default) { [weak self] _ in
            self?.showInputSettings()
        })
        
        // Display Settings
        alert.addAction(UIAlertAction(title: "Display Settings", style: .default) { [weak self] _ in
            self?.showDisplaySettings()
        })
        
        // Radial Control Settings
        alert.addAction(UIAlertAction(title: "Radial Controls", style: .default) { [weak self] _ in
            self?.showRadialControlSettings()
        })
        
        // Network Settings
        alert.addAction(UIAlertAction(title: "Network Settings", style: .default) { [weak self] _ in
            self?.showNetworkSettings()
        })
        
        // Accessibility Settings
        alert.addAction(UIAlertAction(title: "Accessibility", style: .default) { [weak self] _ in
            self?.showAccessibilitySettings()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        present(alert, animated: true)
    }
    
    private func showThemeSettings() {
        showModernThemeSettings()
    }
    
    private func showFontSettings() {
        // Deprecated in favor of ThemeSettingsViewController Typography section
        showModernThemeSettings()
    }
    
    private func editTicker(_ ticker: Ticker) {
        let alert = UIAlertController(title: "Edit Ticker", message: "Modify the ticker settings", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Commands (semicolon separated)"
            textField.text = ticker.commands
            textField.autocapitalizationType = .none
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Interval in seconds"
            textField.keyboardType = .numberPad
            textField.text = "\(ticker.interval)"
        }
        
        alert.addAction(UIAlertAction(title: "Save Changes", style: .default) { _ in
            guard let commands = alert.textFields?[0].text, !commands.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let intervalText = alert.textFields?[1].text, let interval = Double(intervalText), interval > 0 else {
                self.showAlert(title: "Invalid Input", message: "Please enter valid commands and a positive interval in seconds.")
                return
            }
            
            ticker.commands = commands.trimmingCharacters(in: .whitespacesAndNewlines)
            ticker.interval = interval
            ticker.lastModified = Date()
            
            do {
                try ticker.managedObjectContext?.save()
                self.showAlert(title: "Ticker Updated", message: "Ticker has been updated successfully.")
                
                // Restart the ticker with new settings if it's running
                if ticker.isEnabled, let world = ticker.world, self.currentWorld?.objectID == world.objectID {
                    self.stopTicker(ticker)
                    self.startTicker(ticker)
                }
            } catch {
                self.showAlert(title: "Save Error", message: "Failed to update ticker: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Toggle Enabled", style: .default) { _ in
            ticker.isEnabled.toggle()
            ticker.lastModified = Date()
            
            do {
                try ticker.managedObjectContext?.save()
                let status = ticker.isEnabled ? "enabled" : "disabled"
                self.showAlert(title: "Ticker \(status.capitalized)", message: "Ticker has been \(status).")
                
                // Start or stop the ticker based on new state
                if ticker.isEnabled, let world = ticker.world, self.currentWorld?.objectID == world.objectID {
                    self.startTicker(ticker)
                } else {
                    self.stopTicker(ticker)
                }
            } catch {
                self.showAlert(title: "Save Error", message: "Failed to update ticker: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Delete Ticker", style: .destructive) { _ in
            self.confirmDeleteTicker(ticker)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func confirmDeleteTicker(_ ticker: Ticker) {
        let alert = UIAlertController(title: "Delete Ticker", message: "Are you sure you want to delete this ticker?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.stopTicker(ticker)
            
            let context = ticker.managedObjectContext!
            context.delete(ticker)
            
            do {
                try context.save()
                self.showAlert(title: "Ticker Deleted", message: "Ticker has been deleted.")
            } catch {
                self.showAlert(title: "Delete Error", message: "Failed to delete ticker: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    // MARK: - Ticker Management
    
    private var activeTickerTimers: [NSManagedObjectID: Timer] = [:]
    
    private func startTicker(_ ticker: Ticker) {
        guard ticker.isEnabled else { return }
        
        // Stop existing timer if any
        stopTicker(ticker)
        
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(ticker.interval), repeats: true) { [weak self] _ in
            self?.executeTickerCommands(ticker)
        }
        
        activeTickerTimers[ticker.objectID] = timer
        print("Started ticker: \(ticker.commands ?? "") every \(ticker.interval) seconds")
    }
    
    private func stopTicker(_ ticker: Ticker) {
        activeTickerTimers[ticker.objectID]?.invalidate()
        activeTickerTimers.removeValue(forKey: ticker.objectID)
        print("Stopped ticker: \(ticker.commands ?? "")")
    }
    
    private func executeTickerCommands(_ ticker: Ticker) {
        guard let commands = ticker.commands, !commands.isEmpty, isConnected else { return }
        
        let commandList = commands.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        for command in commandList where !command.isEmpty {
            mudSocket?.send(command)
            
            // Show in local echo if enabled
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.localEcho) {
                mudView?.appendTextWithColor("> \(command) [ticker]\n", color: themeManager.linkColor.withAlphaComponent(0.5))
            }
        }
    }
    
    private func startAllTickersForCurrentWorld() {
        guard let world = currentWorld else { return }
        
        let tickers = Array(world.tickers ?? []).filter { $0.isEnabled && !$0.isHidden }
        for ticker in tickers {
            startTicker(ticker)
        }
    }
    
    private func stopAllTickers() {
        for timer in activeTickerTimers.values {
            timer.invalidate()
        }
        activeTickerTimers.removeAll()
    }
    
    // MARK: - Settings Methods
    
    private func showGagsMenu(world: World) {
        let alert = UIAlertController(title: "Gags", message: "Manage text filtering", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Create New Gag", style: .default) { _ in
            self.showCreateGagDialog(for: world)
        })
        
        alert.addAction(UIAlertAction(title: "View All Gags", style: .default) { _ in
            self.showGagsList(for: world)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showTickersMenu(world: World) {
        let alert = UIAlertController(title: "Tickers", message: "Manage automated commands", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Create New Ticker", style: .default) { _ in
            self.showCreateTickerDialog(for: world)
        })
        
        alert.addAction(UIAlertAction(title: "View All Tickers", style: .default) { _ in
            self.showTickersList(for: world)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showInputSettings() {
        showModernInputSettings()
    }
    
    private func showDisplaySettings() {
        // Deprecated in favor of ThemeSettingsViewController Display Options section
        showModernThemeSettings()
    }
    
    private func showRadialControlSettings() {
        let alert = UIAlertController(title: "Radial Controls", message: "Configure radial button positions, style, and commands", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Left Radial Position", style: .default) { _ in
            self.showRadialPositionSelector(isLeftRadial: true)
        })
        
        alert.addAction(UIAlertAction(title: "Right Radial Position", style: .default) { _ in
            self.showRadialPositionSelector(isLeftRadial: false)
        })
        
        alert.addAction(UIAlertAction(title: "Radial Control Style", style: .default) { _ in
            self.showRadialStyleSelector()
        })
        
        // Add label visibility toggle
        let labelsVisible = RadialControl.radialControlLabelsVisible()
        let labelTitle = labelsVisible ? "Hide Labels" : "Show Labels"
        alert.addAction(UIAlertAction(title: labelTitle, style: .default) { _ in
            RadialControl.setRadialControlLabelsVisible(!labelsVisible)
            // Labels updated silently - keep persistent menu open
            self.refreshCurrentPersistentMenu()
            // Notify MudView to update
            NotificationCenter.default.post(name: Notification.Name("RadialControlStyleChanged"), object: nil)
        })
        
        // Add command customization options
        alert.addAction(UIAlertAction(title: "Customize Left Radial Commands", style: .default) { _ in
            self.showRadialCommandCustomization(for: 0)
        })
        
        alert.addAction(UIAlertAction(title: "Customize Right Radial Commands", style: .default) { _ in
            self.showRadialCommandCustomization(for: 1)
        })
        
        alert.addAction(UIAlertAction(title: "Reset All Radial Commands", style: .destructive) { _ in
            self.resetAllRadialControls()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showRadialStyleSelector() {
        let alert = UIAlertController(title: "Radial Control Style", message: "Choose a style for the radial controls", preferredStyle: .actionSheet)
        let currentStyle = RadialControl.radialControlStyle()
        
        for style in RadialControlStyle.allCases {
            let title = style.displayName + (style == currentStyle ? " ✓" : "")
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                RadialControl.setRadialControlStyle(style)
                // Style changed silently - keep persistent menu open
                self.refreshCurrentPersistentMenu()
                // Optionally, notify MudView to update its style
                NotificationCenter.default.post(name: Notification.Name("RadialControlStyleChanged"), object: nil)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showNetworkSettings() {
        // Deprecated in favor of InputSettingsViewController Network section
        showModernInputSettings()
    }
    
    private func showAccessibilitySettings() {
        let alert = UIAlertController(title: "Accessibility", message: "Configure accessibility options", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "VoiceOver Support", style: .default) { _ in
            self.showAlert(title: "VoiceOver", message: "VoiceOver support is built-in and automatically enabled when VoiceOver is active.")
        })
        
        alert.addAction(UIAlertAction(title: "Dynamic Type", style: .default) { _ in
            self.showAlert(title: "Dynamic Type", message: "Dynamic Type support is enabled. Font sizes will adjust based on your system settings.")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    // MARK: - Helper Methods for Settings
    
    private func showCreateGagDialog(for world: World) {
        let alert = UIAlertController(title: "Create Gag", message: "Enter text to hide", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Text to hide"
            textField.autocapitalizationType = .none
        }
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
            guard let gagText = alert.textFields?[0].text, !gagText.isEmpty else { return }
            
            let context = world.managedObjectContext!
            let gag = Gag(context: context)
            gag.gag = gagText
            gag.world = world
            gag.isHidden = false
            gag.lastModified = Date()
            
            do {
                try context.save()
                self.showAlert(title: "Success", message: "Gag created successfully!")
            } catch {
                self.showAlert(title: "Error", message: "Failed to create gag: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showGagsList(for world: World) {
        let gagsListVC = GagsListViewController(world: world)
        let navController = UINavigationController(rootViewController: gagsListVC)
        present(navController, animated: true)
    }
    
    private func showCreateTickerDialog(for world: World) {
        let alert = UIAlertController(title: "Create Ticker", message: "Create an automated command", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Commands (semicolon separated)"
            textField.autocapitalizationType = .none
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Interval in seconds"
            textField.keyboardType = .numberPad
            textField.text = "30"
        }
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { _ in
            guard let commands = alert.textFields?[0].text, !commands.isEmpty,
                  let intervalText = alert.textFields?[1].text, let interval = Double(intervalText), interval > 0 else {
                self.showAlert(title: "Invalid Input", message: "Please enter valid commands and interval")
                return
            }
            
            let context = world.managedObjectContext!
            let ticker = Ticker(context: context)
            ticker.commands = commands
            ticker.interval = interval
            ticker.world = world
            ticker.isHidden = false
            ticker.isEnabled = true
            ticker.lastModified = Date()
            
            do {
                try context.save()
                self.showAlert(title: "Success", message: "Ticker created successfully!")
            } catch {
                self.showAlert(title: "Error", message: "Failed to create ticker: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showTickersList(for world: World) {
        let tickersListVC = TickersListViewController(world: world)
        let navController = UINavigationController(rootViewController: tickersListVC)
        present(navController, animated: true)
    }
    
    private func showThemeSelector() {
        let alert = UIAlertController(title: "Select Theme", message: "Choose a color theme", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Dark Theme", style: .default) { [self] _ in
            self.themeManager.setTheme(at: 0) // Classic Dark
            self.showAlert(title: "Theme Changed", message: "Dark theme applied")
        })
        
        alert.addAction(UIAlertAction(title: "Light Theme", style: .default) { [self] _ in
            self.themeManager.setTheme(at: 1) // Classic Light
            self.showAlert(title: "Theme Changed", message: "Light theme applied")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showFontSizeSelector() {
        let alert = UIAlertController(title: "Font Size", message: "Adjust font size", preferredStyle: .alert)
        
        alert.addTextField { [self] textField in
            textField.placeholder = "Font size (8-24)"
            textField.keyboardType = .numberPad
            textField.text = "\(Int(self.themeManager.currentTheme.fontSize))"
        }
        
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [self] _ in
            guard let sizeText = alert.textFields?[0].text, let size = Float(sizeText), size >= 8 && size <= 24 else {
                self.showAlert(title: "Invalid Size", message: "Please enter a font size between 8 and 24")
                return
            }
            
            self.themeManager.updateFont(name: self.themeManager.currentTheme.fontName, size: CGFloat(size))
            self.showAlert(title: "Font Size Changed", message: "Font size set to \(Int(size))")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showRadialPositionSelector(isLeftRadial: Bool) {
        let side = isLeftRadial ? "Left" : "Right"
        let alert = UIAlertController(title: "\(side) Radial Position", message: "Choose position for \(side.lowercased()) radial controls", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Top", style: .default) { _ in
            let key = isLeftRadial ? UserDefaultsKeys.leftRadialPosition : UserDefaultsKeys.rightRadialPosition
            UserDefaults.standard.set("top", forKey: key)
            // Position changed silently - keep persistent menu open
            self.refreshCurrentPersistentMenu()
        })
        
        alert.addAction(UIAlertAction(title: "Middle", style: .default) { _ in
            let key = isLeftRadial ? UserDefaultsKeys.leftRadialPosition : UserDefaultsKeys.rightRadialPosition
            UserDefaults.standard.set("middle", forKey: key)
            // Position changed silently - keep persistent menu open
            self.refreshCurrentPersistentMenu()
        })
        
        alert.addAction(UIAlertAction(title: "Bottom", style: .default) { _ in
            let key = isLeftRadial ? UserDefaultsKeys.leftRadialPosition : UserDefaultsKeys.rightRadialPosition
            UserDefaults.standard.set("bottom", forKey: key)
            // Position changed silently - keep persistent menu open
            self.refreshCurrentPersistentMenu()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    // MARK: - Debug Methods
    

    

    // MARK: - App State Handling
    
    func handleAppStateChange(_ notificationName: Notification.Name) {
        switch notificationName {
        case .appDidBecomeActive:
            // App became active - check connection status and refresh theme
            if currentWorld != nil, !isConnected {
                connect()
            }
            // Optional: stop background audio on foreground resume
            if SilentAudioManager.shared.isBackgroundAudioPlaying() {
                SilentAudioManager.shared.stopBackgroundAudio()
            }
            
        case .appDidEnterBackground:
            // App entered background - ensure we send a keep-alive
            if isConnected {
                // The MUDSocket will handle sending keep-alive automatically
            }
            // Start silent background audio to help keep session alive (if enabled)
            SilentAudioManager.shared.startBackgroundAudio()
            
        case .appWillResignActive:
            // App will resign active - prepare for background
            break
            
        case .appWillEnterForeground:
            // App will enter foreground - prepare for reconnection
            break
            
        default:
            break
        }
    }
    
    @objc private func handleRadialButtonCommand(_ notification: Notification) {
        guard let command = notification.object as? String else { return }
        
        // Send the command
        processCommand(command)
        
        // Show in local echo if enabled
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.localEcho) {
            mudView?.appendTextWithColor("> \(command) [radial]\n", color: themeManager.linkColor.withAlphaComponent(0.7))
        }
    }
    
    @objc private func handleTriggerCommand(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let commands = userInfo["commands"] as? [String] else {
            return
        }
        
        for command in commands {
            processCommand(command)
            
            // Show in local echo if enabled
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.localEcho) {
                mudView?.appendTextWithColor("> \(command) [trigger]\n", color: themeManager.linkColor.withAlphaComponent(0.7))
            }
        }
    }
    
    private func updateTriggerNotificationObserver() {
        // Remove any existing trigger notification observer
        NotificationCenter.default.removeObserver(self, name: .triggerDidFire, object: nil)
        
        // Add new observer only for the current world
        if let world = currentWorld {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTriggerCommand(_:)),
                name: .triggerDidFire,
                object: world
            )
        }
    }
    
    // MARK: - MudViewDelegate Protocol Methods
    
    func mudView(_ mudView: MudView, didRequestCreateTriggerWithPattern pattern: String) {
        guard let world = currentWorld else { return }
        createPersistentTrigger(world: world, withPattern: pattern)
    }
    
    func mudView(_ mudView: MudView, didRequestCreateAdvancedTriggerWithPattern pattern: String) {
        guard let world = currentWorld else { return }
        createPersistentTrigger(world: world, withPattern: pattern)
    }
    
    func mudView(_ mudView: MudView, didRequestCreateGagWithPattern pattern: String) {
        guard let world = currentWorld else { return }
        createGag(world: world, withPattern: pattern)
    }
    
    private func createPersistentTrigger(world: World, withPattern pattern: String) {
        let alert = UIAlertController(
            title: "➕ New Trigger", 
            message: "Create a trigger with editable pattern and commands", 
            preferredStyle: .alert
        )
        
        // Add pattern text field
        alert.addTextField { textField in
            textField.placeholder = "Pattern (e.g., 'tells you')"
            textField.text = pattern
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        // Multi-line command input
        let textViewController = UIViewController()
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = UIColor.systemBackground
        textView.text = "say Trigger activated!"
        
        textViewController.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: textViewController.view.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: textViewController.view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: textViewController.view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: textViewController.view.bottomAnchor, constant: -8),
            textView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        alert.setValue(textViewController, forKey: "contentViewController")
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let patternField = alert.textFields?.first,
                  let editedPattern = patternField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !editedPattern.isEmpty,
                  !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self?.showAlert(title: "Missing Information", message: "Please enter both pattern and commands")
                return
            }
            
            // Auto-detect trigger type based on edited pattern
            let type = self?.detectTriggerType(from: editedPattern) ?? .substring
            
            // Convert multi-line text to semicolon-separated commands
            let lines = textView.text.components(separatedBy: .newlines)
            let commands = lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            
            let context = world.managedObjectContext!
            let _ = Trigger.createMushClientTrigger(
                pattern: editedPattern,
                commands: commands,
                type: type,
                options: [.enabled, .ignoreCase],
                priority: 50,
                group: nil,
                label: nil,
                world: world,
                context: context
            )
            
            do {
                try context.save()
                // Trigger created silently - keep persistent menu open
                self?.refreshCurrentPersistentMenu()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to create trigger: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func createGag(world: World, withPattern pattern: String) {
        let alert = UIAlertController(title: "Create Gag", message: "Hide text matching: \"\(pattern)\"", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            let context = world.managedObjectContext!
            let gag = Gag(context: context)
            gag.gag = pattern
            gag.world = world
            gag.isHidden = false
            gag.lastModified = Date()
            
            do {
                try context.save()
                self?.showAlert(title: "✅ Gag Created", message: "Text matching \"\(pattern)\" will now be hidden.")
            } catch {
                self?.showAlert(title: "Error", message: "Failed to create gag: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func detectTriggerType(from pattern: String) -> Trigger.TriggerType {
        // Auto-detect trigger type based on pattern content
        if pattern.contains("*") || pattern.contains("?") {
            return .wildcard
        } else if pattern.hasPrefix("^") || pattern.hasSuffix("$") || pattern.contains("[") || pattern.contains("\\") {
            return .regex
        } else {
            return .substring
        }
    }
    
    private func iconForTriggerType(_ type: Trigger.TriggerType) -> String {
        switch type {
        case .substring:
            return "📝"
        case .wildcard:
            return "🌟"
        case .regex:
            return "🔧"
        case .exact:
            return "🎯"
        case .beginsWith:
            return "⏩"
        case .endsWith:
            return "⏸"
        }
    }
    
    private func showTriggerHelp() {
        let helpMessage = """
        📚 Trigger Help
        
        🔹 Substring: Matches exact text anywhere in a line
        Example: "tells you" matches "Bob tells you hello"
        
        🔹 Wildcard: Uses * and ? for pattern matching
        • * matches any text
        • ? matches any single character
        Example: "* tells you *" matches "Bob tells you hello"
        
        🔹 Regular Expression: Advanced pattern matching
        Example: "^(\\w+) tells you (.+)$" captures name and message
        
        💡 Tips:
        • Use variables like $1, $2 in commands to capture text
        • Test patterns before saving
        • Simpler patterns are faster
        """
        
        showAlert(title: "Trigger Help", message: helpMessage)
    }
    
    private func createTrigger(world: World) {
        let alert = UIAlertController(title: "➕ Create New Trigger", message: "Create a trigger to automatically respond to text", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Enter pattern (e.g., 'tells you')"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        // Multi-line command input
        let textViewController = UIViewController()
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = UIColor.systemBackground
        textView.text = "say Hello!"
        
        textViewController.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: textViewController.view.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: textViewController.view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: textViewController.view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: textViewController.view.bottomAnchor, constant: -8),
            textView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        alert.setValue(textViewController, forKey: "contentViewController")
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let pattern = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty,
                  !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self?.showAlert(title: "Missing Information", message: "Please enter both pattern and commands")
                return
            }
            
            // Auto-detect trigger type
            let type = self?.detectTriggerType(from: pattern) ?? .substring
            
            // Convert multi-line text to semicolon-separated commands
            let lines = textView.text.components(separatedBy: .newlines)
            let commands = lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            
            let context = world.managedObjectContext!
            _ = Trigger.createMushClientTrigger(
                pattern: pattern,
                commands: commands,
                type: type,
                options: [.enabled, .ignoreCase],
                priority: 50,
                group: nil,
                label: nil,
                world: world,
                context: context
            )
            
            do {
                try context.save()
                // Trigger created silently - keep persistent menu open
                self?.refreshCurrentPersistentMenu()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to create trigger: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showTriggerTypeSelector(currentType: Trigger.TriggerType, completion: @escaping (Trigger.TriggerType) -> Void) {
        let alert = UIAlertController(title: "Select Trigger Type", message: "Choose how the pattern should match", preferredStyle: .actionSheet)
        
        for type in [Trigger.TriggerType.substring, .wildcard, .regex] {
            let icon = iconForTriggerType(type)
            let isSelected = type == currentType
            let title = "\(icon) \(type.displayName)" + (isSelected ? " ✓" : "")
            
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                completion(type)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showTriggerOptionsSelector(currentOptions: Set<Trigger.TriggerOption>, completion: @escaping (Set<Trigger.TriggerOption>) -> Void) {
        let alert = UIAlertController(title: "Trigger Options", message: "Configure trigger behavior", preferredStyle: .actionSheet)
        
        var selectedOptions = currentOptions
        
        for option in Trigger.TriggerOption.allCases {
            let isSelected = selectedOptions.contains(option)
            let title = "\(option.displayName)" + (isSelected ? " ✓" : "")
            
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                if selectedOptions.contains(option) {
                    selectedOptions.remove(option)
                } else {
                    selectedOptions.insert(option)
                }
                completion(selectedOptions)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Done", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showAliasOptionsMenu(_ alias: Alias, world: World) {
        let alert = UIAlertController(
            title: "📋 \(alias.name ?? "Unknown")", 
            message: "Commands: \(alias.commands ?? "")", 
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "✏️ Edit", style: .default) { [weak self] _ in
            self?.editPersistentAlias(alias, world: world, returnTo: { [weak self] in
                self?.showAliasOptionsMenu(alias, world: world)
            })
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Delete", style: .destructive) { [weak self] _ in
            self?.deleteAlias(alias, world: world, returnTo: { [weak self] in
                self?.showPersistentAliasesMenu(world: world)
            })
        })
        
        alert.addAction(UIAlertAction(title: "← Back to Aliases", style: .cancel) { [weak self] _ in
            self?.showPersistentAliasesMenu(world: world)
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showTriggerOptionsMenu(_ trigger: Trigger, world: World) {
        let statusIcon = trigger.isActive ? "🟢" : "🔴"
        let typeIcon = iconForTriggerType(trigger.triggerTypeEnum)
        
        let alert = UIAlertController(
            title: "\(statusIcon) \(typeIcon) \(trigger.displayName)", 
            message: "Pattern: \(trigger.trigger ?? "")\nCommands: \(trigger.commands ?? "")", 
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "✏️ Edit", style: .default) { [weak self] _ in
            self?.editPersistentMushClientTrigger(trigger, world: world, returnTo: { [weak self] in
                self?.showTriggerOptionsMenu(trigger, world: world)
            })
        })
        
        let toggleTitle = trigger.isActive ? "🔴 Disable" : "🟢 Enable"
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { [weak self] _ in
            self?.toggleTrigger(trigger, returnTo: { [weak self] in
                self?.showTriggerOptionsMenu(trigger, world: world)
            })
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Delete", style: .destructive) { [weak self] _ in
            self?.deleteTriggerLegacy(trigger, returnTo: { [weak self] in
                self?.showPersistentTriggerMenu(world: world)
            })
        })
        
        alert.addAction(UIAlertAction(title: "← Back to Triggers", style: .cancel) { [weak self] _ in
            self?.showPersistentTriggerMenu(world: world)
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    // MARK: - XTERM256/luaxterm256 Response Debugging
    private var awaitingXterm256Response = false
    
    func setAwaitingXterm256Response() {
        awaitingXterm256Response = true
    }
    
    func handleXterm256ServerResponse(_ response: String) {
                        // Server response received
        awaitingXterm256Response = false
    }
}

// MARK: - InputToolbarDelegate

extension ClientViewController: InputToolbarDelegate {
    func inputToolbar(_ toolbar: InputToolbar, didSendText text: String) {
        // If empty input, send a normalized CRLF to server
        if text.isEmpty {
            mudSocket?.send("")
            return
        }
        
        // Check for multi-session commands (#all or #sessionname)
        if text.hasPrefix("#") {
            processMultiSessionCommand(text)
            return
        }
        
        // Process aliases if any
        if let world = currentWorld,
           let aliasCommands = world.commandsForMatchingAlias(input: text) {
            for command in aliasCommands {
                // Check if this is a multi-session command from an alias
                if command.hasPrefix("#") {
                    processMultiSessionCommand(command)
                } else {
                    processCommand(command)
                }
            }
        } else {
            processCommand(text)
        }
        
        // Add to MUD view if local echo is enabled
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.localEcho) {
            mudView?.appendTextWithColor("> \(text)\n", color: themeManager.terminalTextColor)
        }
    }
}

// MARK: - MUDSocketDelegate

extension ClientViewController: MUDSocketDelegate {
    func mudSocket(_ socket: MUDSocket, didConnectToHost host: String, port: UInt16) {
        mudView.appendTextWithColor("Connected to \(host):\(port)\n", color: themeManager.linkColor)
        
        // Update lastConnected timestamp
        if let world = currentWorld {
            world.lastConnected = Date()
            try? world.managedObjectContext?.save()
        }
        
        // Update UI
        updateConnectionStatus()
        
        // Notify delegate
        delegate?.clientDidConnect(self)
        
        // Start tickers for this world
        startAllTickersForCurrentWorld()
        
        // Send login credentials if available
        if let world = currentWorld {
            if let username = world.username, !username.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.mudSocket?.send(username)
                }
                
                if let password = world.password, !password.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.mudSocket?.send(password)
                    }
                }
            }
        }
    }
    
    func mudSocket(_ socket: MUDSocket, didDisconnectWithError error: Error?) {
        if let error = error {
            mudView.appendText("Connection error: \(error.localizedDescription)\n", color: .red)
        } else {
            mudView.appendText("Disconnected.\n", color: themeManager.linkColor)
        }
        
        // Stop all tickers when disconnected
        stopAllTickers()
        
        updateConnectionStatus()
        delegate?.clientDidDisconnect(self)
    }
    
    func mudSocket(_ socket: MUDSocket, didReceiveData data: Data) {
        // Handle xterm256/luaxterm256 response
        if awaitingXterm256Response {
            awaitingXterm256Response = false
        }
        
        // Process data on background queue for better performance
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Filter out telnet negotiation sequences and problematic bytes
            let filteredData = self.filterTelnetData(data)
            
            // Convert data to string with better error handling
            guard let decodedText = self.decodeData(filteredData) else {
                return
            }
            
            // Clean up the text to remove problematic characters
            let cleanedText = self.cleanText(decodedText)
            
            // Process ANSI codes and convert to attributed string
            let attributedText = self.ansiProcessor.processText(cleanedText)
            
            // Move back to main queue for UI updates and trigger processing
            DispatchQueue.main.async {
                // Process triggers on ANSI-cleaned text (keep on main queue for Core Data)
                if let world = self.currentWorld {
                    let triggerText = attributedText.string
                    
                    // Process triggers but defer expensive operations
                    world.processTriggersForText(triggerText, loggingCallback: { [weak self] line, shouldLog in
                        if shouldLog {
                            // Defer logging to background queue
                            DispatchQueue.global(qos: .utility).async {
                                self?.sessionLogger.writeReceivedText(line)
                                // Check for log rotation every 100 lines to avoid frequent file system calls
                                if Int.random(in: 1...100) == 1 {
                                    self?.sessionLogger.checkAndRotateLogIfNeeded()
                                }
                            }
                        }
                    })
                }
                
                // Process gags
                var finalText = attributedText
                if let world = self.currentWorld {
                    let plainText = attributedText.string
                    // Fallback vitals scan from inline status lines (for servers without MSDP/GMCP)
                    self.scanForInlineVitals(in: plainText)
                    if !world.shouldGagText(plainText) {
                        finalText = attributedText
                    } else {
                        return // Text is gagged, don't display
                    }
                }
                
                // Display in MUD view
                self.mudView.appendAttributedText(finalText)
                
                // Notify delegate
                self.delegate?.clientDidReceiveText(self)
            }
        }
    }

    // MARK: - Inline Vitals Fallback (non-OOB)
    private func scanForInlineVitals(in text: String) {
        guard let worldID = worldObjectID else { return }
        // Quick patterns:
        // 1) "< 43985H 9413M 8963V" style
        // 2) "HP: 123/456  Mana: 789/1011" style (case-insensitive)
        let lines = text.split(separator: "\n")
        for rawLine in lines {
            let line = String(rawLine)
            // Pattern 1
            if let match = line.range(of: #"\<\s*(\d+)H\s+(\d+)M(?:\s+(\d+)V)?"#, options: .regularExpression) {
                let substr = String(line[match])
                let nums = substr.replacingOccurrences(of: "<", with: "").split(whereSeparator: { !$0.isNumber })
                if nums.count >= 2, let hp = Int(nums[0]), let mn = Int(nums[1]) {
                    var vars: [String: String] = ["HP": String(hp), "MANA": String(mn)]
                    SessionVitalsStore.shared.update(worldID: worldID, with: vars)
                    continue
                }
            }
            // Pattern 2
            if let regex = try? NSRegularExpression(pattern: #"(?i)HP\s*:?\s*(\d+)(?:/(\d+))?.*?M(?:ANA|N)?\s*:?\s*(\d+)(?:/(\d+))?"#, options: []) {
                let range = NSRange(location: 0, length: line.utf16.count)
                if let m = regex.firstMatch(in: line, options: [], range: range) {
                    func group(_ idx: Int) -> Int? {
                        let r = m.range(at: idx)
                        if r.location != NSNotFound, let swiftRange = Range(r, in: line) { return Int(line[swiftRange]) }
                        return nil
                    }
                    let hp = group(1)
                    let hpMax = group(2)
                    let mn = group(3)
                    let mnMax = group(4)
                    var vars: [String: String] = [:]
                    if let hp { vars["HP"] = String(hp) }
                    if let hpMax { vars["HP_MAX"] = String(hpMax) }
                    if let mn { vars["MANA"] = String(mn) }
                    if let mnMax { vars["MANA_MAX"] = String(mnMax) }
                    if !vars.isEmpty { SessionVitalsStore.shared.update(worldID: worldID, with: vars) }
                }
            }
        }
    }

    func mudSocket(_ socket: MUDSocket, didUpdateLatencyMs latencyMs: Int) {
        // Update latency item in toolbar
        DispatchQueue.main.async {
            self.updateNavigationToolbar()
        }
    }
    
    private func filterTelnetData(_ data: Data) -> Data {
        var filteredData = Data()
        var i = 0
        
        while i < data.count {
            let byte = data[i]
            
            // Check for telnet IAC (Interpret As Command) - 255 (0xFF)
            if byte == 255 && i + 1 < data.count {
                let command = data[i + 1]
                
                // Handle telnet commands
                switch command {
                case 251, 252, 253, 254: // WILL, WON'T, DO, DON'T
                    if i + 2 < data.count {
                        // Skip 3-byte telnet negotiation sequence
                        i += 3
                        continue
                    }
                case 250: // SB (subnegotiation begin)
                    // Find SE (subnegotiation end) - 240
                    var j = i + 2
                    while j < data.count && data[j] != 240 {
                        j += 1
                    }
                    if j < data.count {
                        i = j + 1 // Skip past SE
                        continue
                    }
                default:
                    // Skip 2-byte telnet command
                    i += 2
                    continue
                }
            }
            
            // Filter out other problematic control characters but keep useful ones
            if byte >= 32 || byte == 9 || byte == 10 || byte == 13 || byte == 27 {
                // Keep printable characters, tab, newline, carriage return, and escape
                filteredData.append(byte)
            }
            // Skip other control characters that might cause display issues
            
            i += 1
        }
        
        return filteredData
    }
    
    private func decodeData(_ data: Data) -> String? {
        // Try UTF-8 first
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        
        // Try ASCII
        if let text = String(data: data, encoding: .ascii) {
            return text
        }
        
        // Try Latin-1 (ISO 8859-1) which can decode any byte sequence
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        
        // Last resort: lossy UTF-8 conversion
        return String(decoding: data, as: UTF8.self)
    }
    
    private func cleanText(_ text: String) -> String {
        // Remove null characters and other problematic characters
        var cleaned = text.replacingOccurrences(of: "\0", with: "")
        
        // Remove or replace other problematic Unicode characters
        cleaned = cleaned.replacingOccurrences(of: "\u{FFFD}", with: "") // Remove replacement characters
        
        // Remove excessive consecutive question marks that might be encoding artifacts
        cleaned = cleaned.replacingOccurrences(of: "???", with: "?")
        cleaned = cleaned.replacingOccurrences(of: "??", with: "")
        
        return cleaned
    }
    
    func mudSocket(_ socket: MUDSocket, didWriteDataWithTag tag: Int) {
        // Data was sent successfully
    }
    
    func mudSocketDidDisconnect(_ socket: MUDSocket) {
        mudView.appendTextWithColor("Disconnected.\n", color: themeManager.linkColor)
        
        // Update UI
        updateConnectionStatus()
        
        // Notify delegate
        delegate?.clientDidDisconnect(self)
    }
}

// MARK: - Settings Menu Methods

extension ClientViewController {
    
    private func showWorldInfo(world: World) {
        let alert = UIAlertController(title: "World Info", message: "Basic world settings", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "World Name"
            textField.text = world.name
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Hostname"
            textField.text = world.hostname
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Port"
            textField.text = String(world.port)
            textField.keyboardType = .numberPad
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            if let name = alert.textFields?[0].text, !name.isEmpty,
               let hostname = alert.textFields?[1].text, !hostname.isEmpty,
               let portText = alert.textFields?[2].text, let port = Int32(portText) {
                
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Check for duplicate world names (only if name changed)
                if trimmedName != world.name {
                    let context = world.managedObjectContext!
                    let namePredicate = NSPredicate(format: "name == %@ AND isHidden == NO AND self != %@", trimmedName, world)
                    let nameRequest: NSFetchRequest<World> = World.fetchRequest()
                    nameRequest.predicate = namePredicate
                    
                    do {
                        let existingWorlds = try context.fetch(nameRequest)
                        if !existingWorlds.isEmpty {
                            self.showAlert(title: "Duplicate World Name", message: "A world with the name '\(trimmedName)' already exists. Please choose a different name.")
                            return
                        }
                    } catch {
                        self.showAlert(title: "Validation Error", message: "Failed to validate world name: \(error.localizedDescription)")
                        return
                    }
                }
                
                // Save world data (allow duplicate hostnames)
                world.name = trimmedName
                world.hostname = hostname
                world.port = port
                world.lastModified = Date()
                
                do {
                    try world.managedObjectContext?.save()
                    print("World info updated successfully")
                    self.updateUI() // Refresh the UI to show updated world name
                } catch {
                    print("Failed to save world info: \(error)")
                }
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func showAliasesMenu(world: World) {
        showPersistentAliasesMenu(world: world)
    }
    
    private func showPersistentAliasesMenu(world: World) {
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.sorted { $0.name ?? "" < $1.name ?? "" }
        
        let alert = UIAlertController(title: "📝 Aliases", message: "Manage command aliases (\(aliases.count) total)", preferredStyle: .actionSheet)
        
        // Add new alias
        alert.addAction(UIAlertAction(title: "➕ New Alias", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let editor = AliasEditorViewController(world: world)
            editor.onDismiss = { [weak self] in self?.refreshCurrentPersistentMenu() }
            let nav = UINavigationController(rootViewController: editor)
            nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
            self.present(nav, animated: true)
        })
        
        // List existing aliases
        if aliases.isEmpty {
            alert.addAction(UIAlertAction(title: "📭 No aliases yet", style: .default) { _ in })
        } else {
            for alias in aliases {
                let title = "📋 \(alias.name ?? "Unknown") → \(alias.commands ?? "")"
                alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    guard let self = self else { return }
                    let editor = AliasEditorViewController(world: world, alias: alias)
                    editor.onDismiss = { [weak self] in self?.showPersistentAliasesMenu(world: world) }
                    let nav = UINavigationController(rootViewController: editor)
                    nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
                    self.present(nav, animated: true)
                })
            }
        }
        
        // Bulk actions
        if aliases.count > 1 {
            alert.addAction(UIAlertAction(title: "🗑️ Delete All Aliases", style: .destructive) { [weak self] _ in
                self?.deleteAllAliases(world: world)
            })
        }
        
        showPersistentMenu(alert, type: .aliases)
    }
    
    private func createPersistentNewAlias(world: World) {
        let alert = UIAlertController(title: "➕ New Alias", message: "Create a command alias\n\nEnter each command on a separate line:", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Alias name (e.g., 'n', 'getall')"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        // Multi-line command input
        let textViewController = UIViewController()
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = UIColor.systemBackground
        textView.text = "say Hello!"
        
        textViewController.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: textViewController.view.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: textViewController.view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: textViewController.view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: textViewController.view.bottomAnchor, constant: -8),
            textView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        alert.setValue(textViewController, forKey: "contentViewController")
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self?.showAlertThenReturnToPersistent(title: "Missing Information", message: "Please fill in both alias name and commands")
                return
            }
            
            // Convert multi-line text to semicolon-separated commands
            let lines = textView.text.components(separatedBy: .newlines)
            let commands = lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            
            let context = world.managedObjectContext!
            let alias = Alias(context: context)
            alias.name = name
            alias.commands = commands
            alias.world = world
            alias.isHidden = false
            alias.lastModified = Date()
            
            do {
                try context.save()
                // Alias created silently - keep persistent menu open
                self?.refreshCurrentPersistentMenu()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to create alias: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func editPersistentAlias(_ alias: Alias, world: World, returnTo: @escaping () -> Void) {
        let alert = UIAlertController(title: "✏️ Edit Alias", message: "Modify the alias name and commands", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Alias name"
            textField.text = alias.name
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        // Multi-line command input
        let textViewController = UIViewController()
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = UIColor.systemBackground
        textView.text = alias.commands
        
        textViewController.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: textViewController.view.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: textViewController.view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: textViewController.view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: textViewController.view.bottomAnchor, constant: -8),
            textView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        alert.setValue(textViewController, forKey: "contentViewController")
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self?.showAlertThenReturnToPersistent(title: "Missing Information", message: "Please fill in both alias name and commands")
                return
            }
            
            // Convert multi-line text to semicolon-separated commands
            let lines = textView.text.components(separatedBy: .newlines)
            let commands = lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            
            alias.name = name
            alias.commands = commands
            alias.lastModified = Date()
            
            do {
                try alias.managedObjectContext?.save()
                // Alias updated silently - return to alias options menu
                returnTo()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to update alias: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Delete", style: .destructive) { [weak self] _ in
            self?.deleteAlias(alias, world: world, returnTo: { [weak self] in
                self?.showPersistentAliasesMenu(world: world)
            })
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            returnTo()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func deleteAlias(_ alias: Alias, world: World, returnTo: @escaping () -> Void) {
        let alert = UIAlertController(title: "🗑️ Delete Alias", message: "Are you sure you want to delete the alias '\(alias.name ?? "Unknown")'?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            alias.isHidden = true
            alias.lastModified = Date()
            
            do {
                try alias.managedObjectContext?.save()
                // Alias deleted silently - return to appropriate menu
                returnTo()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to delete alias: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            returnTo()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func deleteAllAliases(world: World) {
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }
        let alert = UIAlertController(title: "🗑️ Delete All Aliases", message: "Are you sure you want to delete all \(aliases.count) aliases? This cannot be undone.", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            for alias in aliases {
                alias.isHidden = true
                alias.lastModified = Date()
            }
            
            do {
                try world.managedObjectContext?.save()
                // All aliases deleted silently - keep persistent menu open
                self?.refreshCurrentPersistentMenu()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to delete aliases: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showTriggerMenu(world: World) {
        showPersistentTriggerMenu(world: world)
    }
    
    private func showPersistentTriggerMenu(world: World) {
        let triggers = Trigger.fetchActiveTriggersOrderedByPriority(for: world, context: world.managedObjectContext!)
        let enabledCount = triggers.filter { $0.isActive }.count
        
        let alert = UIAlertController(
            title: "📋 Triggers", 
            message: "\(enabledCount)/\(triggers.count) active", 
            preferredStyle: .actionSheet
        )
        
        // === CREATE ===
        alert.addAction(UIAlertAction(title: "➕ New Trigger", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let editor = TriggerEditorViewController(world: world)
            editor.onDismiss = { [weak self] in self?.showPersistentTriggerMenu(world: world) }
            let nav = UINavigationController(rootViewController: editor)
            nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
            self.present(nav, animated: true)
        })
        
        // === MANAGE ===
        if !triggers.isEmpty {
            alert.addAction(UIAlertAction(title: "📋 All Triggers (\(triggers.count))", style: .default) { [weak self] _ in
                self?.showAllTriggers(world: world)
            })
            
            // Quick access to recent triggers
            let recentTriggers = triggers.prefix(3)
            for trigger in recentTriggers {
                let statusIcon = trigger.isActive ? "🟢" : "🔴"
                let typeIcon = iconForTriggerType(trigger.triggerTypeEnum)
                let title = "\(statusIcon) \(typeIcon) \(trigger.displayName)"
                
                alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    guard let self = self else { return }
                    let editor = TriggerEditorViewController(world: world, trigger: trigger)
                    editor.onDismiss = { [weak self] in self?.showPersistentTriggerMenu(world: world) }
                    let nav = UINavigationController(rootViewController: editor)
                    nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
                    self.present(nav, animated: true)
                })
            }
            
            // Bulk actions
            if enabledCount > 0 {
                alert.addAction(UIAlertAction(title: "🔴 Disable All", style: .destructive) { [weak self] _ in
                    self?.toggleAllTriggers(enabled: false, world: world)
                    self?.refreshCurrentPersistentMenu()
                })
            }
            
            if enabledCount < triggers.count {
                alert.addAction(UIAlertAction(title: "🟢 Enable All", style: .default) { [weak self] _ in
                    self?.toggleAllTriggers(enabled: true, world: world)
                    self?.refreshCurrentPersistentMenu()
                })
            }
        } else {
            alert.addAction(UIAlertAction(title: "📭 No triggers yet", style: .default) { _ in })
        }
        
        // === HELP ===
        alert.addAction(UIAlertAction(title: "❓ Help", style: .default) { [weak self] _ in
            self?.showTriggerHelp()
        })
        
        showPersistentMenu(alert, type: .triggers)
    }
    
    private func createPersistentTrigger(world: World) {
        let alert = UIAlertController(
            title: "➕ New Trigger", 
            message: "When you see this text, run these commands.\n\nTip: Use * for wildcards, like '* tells you *'", 
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Pattern (e.g., 'You are hungry' or '* tells you *')"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.accessibilityHint = "Enter the text pattern that will activate this trigger"
        }
        
        // Multi-line command input
        let textViewController = UIViewController()
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = UIColor.systemBackground
        textView.text = "say Trigger activated!"
        
        textViewController.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: textViewController.view.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: textViewController.view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: textViewController.view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: textViewController.view.bottomAnchor, constant: -8),
            textView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        alert.setValue(textViewController, forKey: "contentViewController")
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let pattern = alert.textFields?[0].text, !pattern.isEmpty,
                  !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self?.showAlertThenReturnToPersistent(title: "Missing Information", message: "Please fill in both pattern and commands")
                return
            }
            
            // Auto-detect trigger type based on pattern
            let type = self?.detectTriggerType(from: pattern) ?? .substring
            
            // Convert multi-line text to semicolon-separated commands
            let lines = textView.text.components(separatedBy: .newlines)
            let commands = lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            
            let context = world.managedObjectContext!
            _ = Trigger.createMushClientTrigger(
                pattern: pattern,
                commands: commands,
                type: type,
                options: [.enabled, .ignoreCase],
                priority: 50,
                group: nil,
                label: nil,
                world: world,
                context: context
            )
            
            do {
                try context.save()
                // Trigger created silently - keep persistent menu open
                self?.refreshCurrentPersistentMenu()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to create trigger: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func editPersistentMushClientTrigger(_ trigger: Trigger, world: World, returnTo: @escaping () -> Void) {
        let alert = UIAlertController(title: "✏️ Edit Trigger", message: "Modify the trigger pattern and commands", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Trigger pattern"
            textField.text = trigger.trigger
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        // Multi-line command input
        let textViewController = UIViewController()
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.systemFont(ofSize: 14)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.backgroundColor = UIColor.systemBackground
        
        // Convert existing semicolon-separated commands back to separate lines
        if let existingCommands = trigger.commands {
            let lines = existingCommands.components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            textView.text = lines.joined(separator: "\n")
        }
        
        textViewController.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: textViewController.view.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: textViewController.view.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: textViewController.view.trailingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: textViewController.view.bottomAnchor, constant: -8),
            textView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        alert.setValue(textViewController, forKey: "contentViewController")
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let pattern = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty,
                  !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self?.showAlertThenReturnToPersistent(title: "Missing Information", message: "Please fill in both pattern and commands")
                return
            }
            
            // Convert multi-line text to semicolon-separated commands
            let lines = textView.text.components(separatedBy: .newlines)
            let commands = lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            
            trigger.trigger = pattern
            trigger.commands = commands
            trigger.lastModified = Date()
            
            do {
                try trigger.managedObjectContext?.save()
                // Trigger updated silently - return to trigger options menu
                returnTo()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to update trigger: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "🔄 Toggle", style: .default) { [weak self] _ in
            self?.toggleTrigger(trigger, returnTo: returnTo)
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Delete", style: .destructive) { [weak self] _ in
            self?.deleteTriggerLegacy(trigger, returnTo: { [weak self] in
                self?.showPersistentTriggerMenu(world: world)
            })
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            returnTo()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func deleteTriggerLegacy(_ trigger: Trigger, returnTo: @escaping () -> Void) {
        let alert = UIAlertController(title: "🗑️ Delete Trigger", message: "Are you sure you want to delete the trigger '\(trigger.displayName)'?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            trigger.isHidden = true
            trigger.lastModified = Date()
            
            do {
                try trigger.managedObjectContext?.save()
                // Trigger deleted silently - return to appropriate menu
                returnTo()
            } catch {
                self?.showAlertThenReturnToPersistent(title: "Error", message: "Failed to delete trigger: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            returnTo()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    // MARK: - Helper Methods
    
    private func showAllTriggers(world: World) {
        let triggers = Trigger.fetchActiveTriggersOrderedByPriority(for: world, context: world.managedObjectContext!)
        let enabledCount = triggers.filter { $0.isActive }.count
        let totalMatches = triggers.reduce(0) { $0 + Int($1.matchCount) }
        
        let alert = UIAlertController(
            title: "📊 All Triggers (\(triggers.count))", 
            message: "✅ Active: \(enabledCount) | ❌ Inactive: \(triggers.count - enabledCount) | 🎯 Total Matches: \(totalMatches)", 
            preferredStyle: .actionSheet
        )
        
        // Group triggers by status for better organization
        let activeTriggers = triggers.filter { $0.isActive }
        let inactiveTriggers = triggers.filter { !$0.isActive }
        
        if !activeTriggers.isEmpty {
            alert.addAction(UIAlertAction(title: "=== ✅ ACTIVE TRIGGERS ===", style: .default) { _ in })
            
            for trigger in activeTriggers.prefix(5) {
                let typeIcon = iconForTriggerType(trigger.triggerTypeEnum)
                let matchText = trigger.matchCount > 0 ? " (\(trigger.matchCount))" : ""
                let priorityText = trigger.priority != 50 ? " [\(trigger.priority)]" : ""
                let title = "\(typeIcon) \(trigger.displayName)\(priorityText)\(matchText)"
                
                alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    self?.editMushClientTrigger(trigger)
                })
            }
            
            if activeTriggers.count > 5 {
                alert.addAction(UIAlertAction(title: "... and \(activeTriggers.count - 5) more active", style: .default) { _ in })
            }
        }
        
        if !inactiveTriggers.isEmpty {
            if !activeTriggers.isEmpty {
                alert.addAction(UIAlertAction(title: "", style: .default) { _ in })
            }
            
            alert.addAction(UIAlertAction(title: "=== ❌ INACTIVE TRIGGERS ===", style: .default) { _ in })
            
            for trigger in inactiveTriggers.prefix(3) {
                let typeIcon = iconForTriggerType(trigger.triggerTypeEnum)
                let title = "❌ \(typeIcon) \(trigger.displayName)"
                
                alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    self?.editMushClientTrigger(trigger)
                })
            }
            
            if inactiveTriggers.count > 3 {
                alert.addAction(UIAlertAction(title: "... and \(inactiveTriggers.count - 3) more inactive", style: .default) { _ in })
            }
        }
        
        if triggers.isEmpty {
            alert.addAction(UIAlertAction(title: "No triggers created yet", style: .default) { _ in })
            alert.addAction(UIAlertAction(title: "➕ Create Your First Trigger", style: .default) { [weak self] _ in
                self?.createTrigger(world: world)
            })
        } else {
            // Management actions
            alert.addAction(UIAlertAction(title: "", style: .default) { _ in })
            
            if enabledCount > 0 {
                alert.addAction(UIAlertAction(title: "🔴 Disable All Triggers", style: .destructive) { [weak self] _ in
                    self?.toggleAllTriggers(enabled: false, world: world)
                })
            }
            
            if enabledCount < triggers.count {
                alert.addAction(UIAlertAction(title: "🟢 Enable All Triggers", style: .default) { [weak self] _ in
                    self?.toggleAllTriggers(enabled: true, world: world)
                })
            }
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    private func toggleAllTriggers(enabled: Bool, world: World) {
        let triggers = Trigger.fetchActiveTriggersOrderedByPriority(for: world, context: world.managedObjectContext!)
        let context = world.managedObjectContext!
        
        for trigger in triggers {
            var options = trigger.triggerOptions
            if enabled {
                options.insert(.enabled)
            } else {
                options.remove(.enabled)
            }
            trigger.triggerOptions = options
            trigger.lastModified = Date()
        }
        
        do {
            try context.save()
            // All triggers toggled silently - keep persistent menu open
            refreshCurrentPersistentMenu()
        } catch {
            showAlertThenReturnToPersistent(title: "Error", message: "Failed to update triggers: \(error.localizedDescription)")
        }
    }
    
    private func showTriggerTester(world: World) {
        let alert = UIAlertController(
            title: "🧪 Pattern Tester", 
            message: "Test trigger patterns against sample text to see how they work", 
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Enter sample text to test..."
            textField.text = "Biscuit tells you 'Hello there!'"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "🔍 Test All Active Triggers", style: .default) { [weak self] _ in
            self?.testAllTriggers(testText: alert.textFields?[0].text ?? "", world: world)
        })
        
        alert.addAction(UIAlertAction(title: "🎯 Test Specific Pattern", style: .default) { [weak self] _ in
            self?.showPatternTestCreator(testText: alert.textFields?[0].text ?? "", world: world)
        })
        
        alert.addAction(UIAlertAction(title: "📚 Use Example Text", style: .default) { [weak self] _ in
            self?.showTestExamples { exampleText in
                alert.textFields?[0].text = exampleText
                self?.presentModalThenReturnToPersistent(alert)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func testAllTriggers(testText: String, world: World) {
        guard !testText.isEmpty else {
            showAlertThenReturnToPersistent(title: "No Test Text", message: "Please enter some text to test")
            return
        }
        
        let triggers = Trigger.fetchActiveTriggersOrderedByPriority(for: world, context: world.managedObjectContext!)
        let activeTriggers = triggers.filter { $0.isActive }
        
        var matchingTriggers: [(Trigger, [String: String], [String])] = []
        
        for trigger in activeTriggers {
            if trigger.matches(line: testText) {
                let variables = trigger.captureVariables(from: testText)
                let commands = trigger.processedCommands(for: testText)
                matchingTriggers.append((trigger, variables, commands))
            }
        }
        
        var resultMessage = "📝 Test Text: \"\(testText)\"\n\n"
        
        if matchingTriggers.isEmpty {
            resultMessage += "❌ No triggers matched this text"
        } else {
            resultMessage += "✅ Found \(matchingTriggers.count) matching trigger(s):\n\n"
            
            for (index, (trigger, variables, commands)) in matchingTriggers.enumerated() {
                let typeIcon = iconForTriggerType(trigger.triggerTypeEnum)
                resultMessage += "\(index + 1). \(typeIcon) \(trigger.displayName)\n"
                resultMessage += "   Pattern: \(trigger.trigger ?? "Unknown")\n"
                
                if !variables.isEmpty {
                    resultMessage += "   Variables: "
                    let sortedVars = variables.sorted { $0.key < $1.key }
                    resultMessage += sortedVars.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: ", ")
                    resultMessage += "\n"
                }
                
                if !commands.isEmpty {
                    resultMessage += "   Commands: \(commands.joined(separator: "; "))\n"
                }
                
                resultMessage += "\n"
            }
        }
        
        let resultAlert = UIAlertController(title: "🧪 Test Results", message: resultMessage, preferredStyle: .alert)
        resultAlert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(resultAlert)
    }
    
    private func showPatternTestCreator(testText: String, world: World) {
        let alert = UIAlertController(
            title: "🎯 Test Custom Pattern", 
            message: "Create a temporary pattern to test", 
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Enter pattern to test..."
            textField.text = "* tells you *"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        // Add trigger type selector
        var selectedType: Trigger.TriggerType = .wildcard
        
        alert.addAction(UIAlertAction(title: "📝 Choose Pattern Type", style: .default) { [weak self] _ in
            self?.showTriggerTypeSelector(currentType: selectedType) { newType in
                selectedType = newType
                
                // Test the pattern
                guard let pattern = alert.textFields?[0].text, !pattern.isEmpty else {
                    self?.showAlert(title: "No Pattern", message: "Please enter a pattern to test")
                    return
                }
                
                self?.testCustomPattern(pattern: pattern, type: selectedType, testText: testText)
            }
        })
        
        alert.addAction(UIAlertAction(title: "🧪 Test as Wildcard", style: .default) { [weak self] _ in
            guard let pattern = alert.textFields?[0].text, !pattern.isEmpty else {
                self?.showAlert(title: "No Pattern", message: "Please enter a pattern to test")
                return
            }
            
            self?.testCustomPattern(pattern: pattern, type: .wildcard, testText: testText)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func testCustomPattern(pattern: String, type: Trigger.TriggerType, testText: String) {
        // Create a temporary trigger for testing
        let context = PersistenceController.shared.container.viewContext
        let testTrigger = Trigger(context: context)
        testTrigger.trigger = pattern
        testTrigger.triggerTypeEnum = type
        testTrigger.isEnabled = true
        testTrigger.isHidden = false
        
        let matches = testTrigger.matches(line: testText)
        let variables = testTrigger.captureVariables(from: testText)
        
        // Don't save the test trigger
        context.rollback()
        
        let typeIcon = iconForTriggerType(type)
        var resultMessage = "📝 Test Text: \"\(testText)\"\n"
        resultMessage += "\(typeIcon) Pattern: \"\(pattern)\"\n"
        resultMessage += "🔧 Type: \(type.displayName)\n\n"
        
        if matches {
            resultMessage += "✅ PATTERN MATCHES!\n\n"
            
            if !variables.isEmpty {
                resultMessage += "📊 Captured Variables:\n"
                let sortedVars = variables.sorted { $0.key < $1.key }
                for (key, value) in sortedVars {
                    resultMessage += "• \(key): \"\(value)\"\n"
                }
            } else {
                resultMessage += "ℹ️ No variables captured (pattern has no capture groups)"
            }
        } else {
            resultMessage += "❌ Pattern does not match\n\n"
            resultMessage += "💡 Tip: Try adjusting your pattern or check the pattern type"
        }
        
        let resultAlert = UIAlertController(title: "🧪 Pattern Test Result", message: resultMessage, preferredStyle: .alert)
        resultAlert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(resultAlert)
    }
    
    private func showTestExamples(completion: @escaping (String) -> Void) {
        let alert = UIAlertController(
            title: "📚 Test Examples", 
            message: "Choose sample text to test your triggers against", 
            preferredStyle: .actionSheet
        )
        
        let examples = [
            ("💬 Chat Message", "Biscuit tells you 'Hello there!'"),
            ("⚔️ Combat", "The orc attacks you for 25 damage!"),
            ("💰 Gold", "You have 1250 gold pieces."),
            ("🏃 Movement", "You go north."),
            ("🎒 Inventory", "You are carrying a sword and a shield."),
            ("🏥 Health", "Your health is 85/100."),
            ("🌟 Level Up", "You have gained a level! You are now level 15."),
            ("📢 Broadcast", "[OOC] Admin: Server restart in 5 minutes"),
            ("🎯 Emote", "Biscuit smiles at you warmly."),
            ("🔔 System", "You feel hungry.")
        ]
        
        for (title, text) in examples {
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                completion(text)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    // MARK: - Individual Trigger Editing Methods
    
    private func editTriggerBasics(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Edit Trigger", message: "Modify pattern and commands", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Pattern"
            textField.text = trigger.trigger
            textField.autocapitalizationType = .none
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Commands"
            textField.text = trigger.commands
            textField.autocapitalizationType = .none
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Label"
            textField.text = trigger.label
            textField.autocapitalizationType = .words
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            trigger.trigger = alert.textFields?[0].text
            trigger.commands = alert.textFields?[1].text
            trigger.label = alert.textFields?[2].text?.isEmpty == false ? alert.textFields?[2].text : nil
            trigger.lastModified = Date()
            
            do {
                try trigger.managedObjectContext?.save()
                // Trigger saved silently - keep persistent menu open
                self.refreshCurrentPersistentMenu()
            } catch {
                self.showAlertThenReturnToPersistent(title: "Error", message: "Failed to save: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func editTriggerOptions(_ trigger: Trigger) {
        showTriggerOptionsSelector(currentOptions: trigger.triggerOptions) { newOptions in
            trigger.triggerOptions = newOptions
            trigger.lastModified = Date()
            
            do {
                try trigger.managedObjectContext?.save()
                // Trigger options saved silently - keep persistent menu open
                self.refreshCurrentPersistentMenu()
            } catch {
                self.showAlertThenReturnToPersistent(title: "Error", message: "Failed to save options: \(error.localizedDescription)")
            }
        }
    }
    
    private func testTriggerPattern(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Test Pattern", message: "Test this trigger's pattern", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Enter test text"
            textField.text = "Biscuit says, 'test'"
        }
        
        alert.addAction(UIAlertAction(title: "Test", style: .default) { _ in
            guard let testText = alert.textFields?[0].text, !testText.isEmpty else {
                return
            }
            
            let matches = trigger.matches(line: testText)
            let variables = trigger.captureVariables(from: testText)
            let commands = trigger.processedCommands(for: testText)
            
            var result = matches ? "✅ MATCHES" : "❌ NO MATCH"
            
            if matches {
                result += "\n\n📝 Variables:"
                for (key, value) in variables.sorted(by: { $0.key < $1.key }) {
                    result += "\n\(key): \"\(value)\""
                }
                
                result += "\n\n⚡ Commands:"
                for command in commands {
                    result += "\n• \(command)"
                }
            }
            
            self.showAlertThenReturnToPersistent(title: "Test Result", message: result)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showTriggerStatistics(_ trigger: Trigger) {
        let message = """
        📊 Trigger Statistics
        
        Pattern: \(trigger.trigger ?? "Unknown")
        Type: \(trigger.triggerTypeEnum.displayName)
        Priority: \(trigger.priority)
        Group: \(trigger.group ?? "Default")
        
        🎯 Performance:
        • Match Count: \(trigger.matchCount)
        • Status: \(trigger.isActive ? "Active" : "Inactive")
        • Last Modified: \(trigger.lastModified?.formatted() ?? "Unknown")
        
        ⚙️ Options:
        \(trigger.triggerOptions.map { "• \($0.displayName)" }.joined(separator: "\n"))
        """
        
        showAlertThenReturnToPersistent(title: "Trigger Statistics", message: message)
    }
    
    private func toggleTrigger(_ trigger: Trigger, returnTo: @escaping () -> Void) {
        var options = trigger.triggerOptions
        if options.contains(.enabled) {
            options.remove(.enabled)
        } else {
            options.insert(.enabled)
        }
        trigger.triggerOptions = options
        trigger.lastModified = Date()
        
        do {
            try trigger.managedObjectContext?.save()
            // Trigger toggled silently - return to appropriate menu
            returnTo()
        } catch {
            showAlertThenReturnToPersistent(title: "Error", message: "Failed to toggle trigger: \(error.localizedDescription)")
        }
    }
    
    private func deleteTrigger(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Delete Trigger", message: "Are you sure you want to delete '\(trigger.displayName)'?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            trigger.managedObjectContext?.delete(trigger)
            
            do {
                try trigger.managedObjectContext?.save()
                // Trigger deleted silently - keep persistent menu open
                self.refreshCurrentPersistentMenu()
            } catch {
                self.showAlertThenReturnToPersistent(title: "Error", message: "Failed to delete trigger: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }

    private func editMushClientTrigger(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Edit Trigger", message: trigger.displayName, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "✏️ Edit Pattern & Commands", style: .default) { _ in
            self.editTriggerBasics(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "⚙️ Edit Options", style: .default) { _ in
            self.editTriggerOptions(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "🎯 Test Pattern", style: .default) { _ in
            self.testTriggerPattern(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "📊 View Statistics", style: .default) { _ in
            self.showTriggerStatistics(trigger)
        })
        
        let toggleTitle = trigger.isActive ? "🔴 Disable" : "🟢 Enable"
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { _ in
            self.toggleTrigger(trigger, returnTo: { [weak self] in
                self?.refreshCurrentPersistentMenu()
            })
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Delete", style: .destructive) { _ in
            self.deleteTrigger(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    // MARK: - Missing MudViewDelegate Methods
    
    func mudView(_ mudView: MudView, didRequestCustomizeRadialButtons button: Int) {
        showPersistentRadialControlMenu()
    }
    
    func mudView(_ mudView: MudView, didRequestResetRadialControls: Void) {
        resetAllRadialControls()
    }
    
    func resetAllRadialControls() {
        let alert = UIAlertController(title: "Reset Radial Controls", message: "This will reset all radial button commands to defaults. Continue?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            // Reset all radial control commands to defaults
            for buttonIndex in 0..<2 {
                for direction in RadialDirection.allCases {
                    let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            
            // Notify MudView to update labels
            NotificationCenter.default.post(name: Notification.Name("RadialControlCommandsChanged"), object: nil)
            
            // Refresh the radial controls
            self?.mudView?.resetAllRadialControls()
            
            // All radial controls reset silently - keep persistent menu open
            self?.refreshCurrentPersistentMenu()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.refreshCurrentPersistentMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
    
    func showPersistentRadialControlMenu() {
        let alert = UIAlertController(title: "🎮 Radial Controls", message: "Customize radial button commands", preferredStyle: .actionSheet)
        
        // Left radial customization
        alert.addAction(UIAlertAction(title: "🎮 Left Radial Commands", style: .default) { [weak self] _ in
            self?.showRadialCommandCustomization(for: 0)
        })
        
        // Right radial customization
        alert.addAction(UIAlertAction(title: "🎮 Right Radial Commands", style: .default) { [weak self] _ in
            self?.showRadialCommandCustomization(for: 1)
        })
        
        // Position settings
        alert.addAction(UIAlertAction(title: "📍 Left Radial Position", style: .default) { [weak self] _ in
            self?.showRadialPositionSelector(isLeftRadial: true)
        })
        
        alert.addAction(UIAlertAction(title: "📍 Right Radial Position", style: .default) { [weak self] _ in
            self?.showRadialPositionSelector(isLeftRadial: false)
        })
        
        // Style settings
        alert.addAction(UIAlertAction(title: "🎨 Control Style", style: .default) { [weak self] _ in
            self?.showRadialStyleSelector()
        })
        
        // Label visibility toggle
        let labelsVisible = RadialControl.radialControlLabelsVisible()
        let labelTitle = labelsVisible ? "🏷️ Hide Labels" : "🏷️ Show Labels"
        alert.addAction(UIAlertAction(title: labelTitle, style: .default) { [weak self] _ in
            RadialControl.setRadialControlLabelsVisible(!labelsVisible)
            self?.showAlertThenReturnToPersistent(title: "✅ Labels Updated", message: "Radial control labels are now \(!labelsVisible ? "visible" : "hidden")")
            NotificationCenter.default.post(name: Notification.Name("RadialControlStyleChanged"), object: nil)
        })
        
        // Reset all commands
        alert.addAction(UIAlertAction(title: "🔄 Reset All Commands", style: .destructive) { [weak self] _ in
            self?.resetAllRadialControls()
        })
        
        showPersistentMenu(alert, type: .radialControls)
    }
    
    func showRadialCommandCustomization(for buttonIndex: Int) {
        let buttonName = buttonIndex == 0 ? "Left" : "Right"
        let alert = UIAlertController(title: "🎮 \(buttonName) Radial Commands", message: "Customize commands for each direction", preferredStyle: .actionSheet)
        
        for direction in RadialDirection.allCases {
            let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
            let currentCommand = UserDefaults.standard.string(forKey: key) ?? direction.defaultCommand
            let title = "\(direction.rawValue.capitalized): \(currentCommand)"
            
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.editRadialCommand(for: buttonIndex, direction: direction)
            })
        }
        
        alert.addAction(UIAlertAction(title: "🔄 Reset to Defaults", style: .destructive) { [weak self] _ in
            self?.resetRadialButton(buttonIndex)
        })
        
        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.showPersistentRadialControlMenu()
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    private func editRadialCommand(for buttonIndex: Int, direction: RadialDirection) {
        let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
        let currentCommand = UserDefaults.standard.string(forKey: key) ?? direction.defaultCommand
        let buttonName = buttonIndex == 0 ? "Left" : "Right"
        
        let alert = UIAlertController(title: "✏️ Edit \(direction.rawValue.capitalized) Command", message: "\(buttonName) Radial\nCurrent: \(currentCommand)", preferredStyle: .actionSheet)
        
        // Common MUD commands
        let commonCommands = [
            ("north", "🧭 North"),
            ("south", "🧭 South"), 
            ("east", "🧭 East"),
            ("west", "🧭 West"),
            ("up", "⬆️ Up"),
            ("down", "⬇️ Down"),
            ("look", "👁️ Look"),
            ("inventory", "🎒 Inventory"),
            ("get all", "🤏 Get All"),
            ("who", "👥 Who"),
            ("score", "📊 Score"),
            ("save", "💾 Save"),
            ("quit", "🚪 Quit")
        ]
        
        // Show current command if it's not in common commands
        if !commonCommands.contains(where: { $0.0 == currentCommand }) {
            alert.addAction(UIAlertAction(title: "✅ Keep: \(currentCommand)", style: .default) { [weak self] _ in
                // Keep current command - just go back
                self?.showRadialCommandCustomization(for: buttonIndex)
            })
        }
        
        // Add common commands
        for (command, displayName) in commonCommands {
            let isSelected = command == currentCommand
            let title = "\(displayName)" + (isSelected ? " ✓" : "")
            
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                UserDefaults.standard.set(command, forKey: key)
                // Notify MudView to update labels
                NotificationCenter.default.post(name: Notification.Name("RadialControlCommandsChanged"), object: nil)
                // Command updated silently - return to radial customization menu
                self?.showRadialCommandCustomization(for: buttonIndex)
            })
        }
        
        // Custom command option
        alert.addAction(UIAlertAction(title: "✏️ Custom Command", style: .default) { [weak self] _ in
            self?.showCustomCommandInput(for: buttonIndex, direction: direction)
        })
        
        // Reset to default
        alert.addAction(UIAlertAction(title: "🔄 Reset to Default (\(direction.defaultCommand))", style: .destructive) { [weak self] _ in
            UserDefaults.standard.removeObject(forKey: key)
            // Notify MudView to update labels
            NotificationCenter.default.post(name: Notification.Name("RadialControlCommandsChanged"), object: nil)
            // Command reset silently - return to radial customization menu
            self?.showRadialCommandCustomization(for: buttonIndex)
        })
        
        alert.addAction(UIAlertAction(title: "← Back", style: .cancel) { [weak self] _ in
            self?.showRadialCommandCustomization(for: buttonIndex)
        })
        
        if let popover = alert.popoverPresentationController {
            if let settingsButton = navigationToolbar.items?.last {
                popover.barButtonItem = settingsButton
            }
        }
        
        presentModalThenReturnToPersistent(alert)
    }
    
    private func showCustomCommandInput(for buttonIndex: Int, direction: RadialDirection) {
        let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
        let currentCommand = UserDefaults.standard.string(forKey: key) ?? direction.defaultCommand
        let buttonName = buttonIndex == 0 ? "Left" : "Right"
        
        let alert = UIAlertController(title: "Custom Command", message: "\(buttonName) Radial - \(direction.rawValue.capitalized)", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Enter command"
            textField.text = currentCommand
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let command = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty {
                UserDefaults.standard.set(command, forKey: key)
                // Notify MudView to update labels
                NotificationCenter.default.post(name: Notification.Name("RadialControlCommandsChanged"), object: nil)
                // Command updated silently - return to radial customization menu
                self?.showRadialCommandCustomization(for: buttonIndex)
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.editRadialCommand(for: buttonIndex, direction: direction)
        })
        
        presentModalThenReturnToPersistent(alert)
    }
    
    private func resetRadialButton(_ buttonIndex: Int) {
        let buttonName = buttonIndex == 0 ? "Left" : "Right"
        let alert = UIAlertController(title: "Reset \(buttonName) Radial", message: "Reset all commands for this radial control to defaults?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            for direction in RadialDirection.allCases {
                let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
                UserDefaults.standard.removeObject(forKey: key)
            }
            // Notify MudView to update labels
            NotificationCenter.default.post(name: Notification.Name("RadialControlCommandsChanged"), object: nil)
            // Radial commands reset silently - return to radial controls menu
            self?.showPersistentRadialControlMenu()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.showPersistentRadialControlMenu()
        })
        presentModalThenReturnToPersistent(alert)
    }
}

// MARK: - GagsListViewController

class GagsListViewController: UIViewController {
    
    private let world: World
    private var tableView: UITableView!
    private var gags: [Gag] = []
    
    init(world: World) {
        self.world = world
        super.init(nibName: nil, bundle: nil)
        title = "Gags"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadGags()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addGag))
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "GagCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadGags() {
        gags = Array(world.gags ?? []).sorted { ($0.gag ?? "") < ($1.gag ?? "") }
        tableView.reloadData()
    }
    
    @objc private func doneTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addGag() {
        let alert = UIAlertController(title: "Create Gag", message: "Enter text to hide", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Text to hide"
            textField.autocapitalizationType = .none
        }
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let gagText = alert.textFields?[0].text,
                  !gagText.isEmpty else { return }
            
            let context = self.world.managedObjectContext!
            let gag = Gag(context: context)
            gag.gag = gagText
            gag.world = self.world
            gag.isEnabled = true
            gag.isHidden = false
            gag.lastModified = Date()
            
            do {
                try context.save()
                self.loadGags()
            } catch {
                self.showAlert(title: "Error", message: "Failed to create gag: \\(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func editGag(_ gag: Gag) {
        let alert = UIAlertController(title: "Edit Gag", message: "Modify the text pattern", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.text = gag.gag
            textField.placeholder = "Text to hide"
            textField.autocapitalizationType = .none
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let gagText = alert.textFields?[0].text,
                  !gagText.isEmpty else { return }
            
            gag.gag = gagText
            gag.lastModified = Date()
            
            do {
                try gag.managedObjectContext?.save()
                self.loadGags()
            } catch {
                self.showAlert(title: "Error", message: "Failed to update gag: \\(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func toggleGag(_ gag: Gag) {
        gag.isEnabled.toggle()
        gag.lastModified = Date()
        
        do {
            try gag.managedObjectContext?.save()
            loadGags()
        } catch {
            showAlert(title: "Error", message: "Failed to toggle gag: \\(error.localizedDescription)")
        }
    }
    
    private func deleteGag(_ gag: Gag) {
        let alert = UIAlertController(
            title: "Delete Gag",
            message: "Are you sure you want to delete this gag?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            let context = gag.managedObjectContext!
            context.delete(gag)
            
            do {
                try context.save()
                self.loadGags()
            } catch {
                self.showAlert(title: "Error", message: "Failed to delete gag: \\(error.localizedDescription)")
            }
        })
        
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - GagsListViewController Table View

extension GagsListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return gags.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "GagCell", for: indexPath)
        let gag = gags[indexPath.row]
        
        cell.textLabel?.text = gag.gag ?? "Unnamed Gag"
        cell.detailTextLabel?.text = gag.isEnabled ? "Enabled" : "Disabled"
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cell.textLabel?.textColor = gag.isEnabled ? ThemeManager.shared.currentTheme.fontColor : ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.5)
        cell.detailTextLabel?.textColor = gag.isEnabled ? .systemGreen : .systemRed
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let gag = gags[indexPath.row]
        
        let alert = UIAlertController(title: gag.gag, message: "Choose an action", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Edit", style: .default) { [weak self] _ in
            self?.editGag(gag)
        })
        
        let toggleTitle = gag.isEnabled ? "Disable" : "Enable"
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { [weak self] _ in
            self?.toggleGag(gag)
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteGag(gag)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return gags.isEmpty ? nil : "\\(gags.count) Gag(s)"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return gags.isEmpty ? "No gags created yet. Tap + to add one." : "Gags hide matching text from the terminal output."
    }
}

// MARK: - TickersListViewController

class TickersListViewController: UIViewController {
    
    private let world: World
    private var tableView: UITableView!
    private var tickers: [Ticker] = []
    
    init(world: World) {
        self.world = world
        super.init(nibName: nil, bundle: nil)
        title = "Tickers"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadTickers()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTicker))
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TickerCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadTickers() {
        tickers = Array(world.tickers ?? []).sorted { $0.interval < $1.interval }
        tableView.reloadData()
    }
    
    @objc private func doneTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addTicker() {
        let alert = UIAlertController(title: "Create Ticker", message: "Configure automatic commands", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Commands (semicolon separated)"
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Interval in seconds"
            textField.keyboardType = .numberPad
        }
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let commands = alert.textFields?[0].text,
                  !commands.isEmpty,
                  let intervalText = alert.textFields?[1].text,
                  let interval = Int32(intervalText),
                  interval > 0 else { return }
            
            let context = self.world.managedObjectContext!
            let ticker = Ticker(context: context)
            ticker.commands = commands
            ticker.interval = Double(interval)
            ticker.world = self.world
            ticker.isEnabled = true
            ticker.isHidden = false
            ticker.lastModified = Date()
            
            do {
                try context.save()
                self.loadTickers()
            } catch {
                self.showAlert(title: "Error", message: "Failed to create ticker: \\(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func editTicker(_ ticker: Ticker) {
        let alert = UIAlertController(title: "Edit Ticker", message: "Modify ticker settings", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.text = ticker.commands
            textField.placeholder = "Commands (semicolon separated)"
        }
        
        alert.addTextField { textField in
            textField.text = "\\(ticker.interval)"
            textField.placeholder = "Interval in seconds"
            textField.keyboardType = .numberPad
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let commands = alert.textFields?[0].text,
                  !commands.isEmpty,
                  let intervalText = alert.textFields?[1].text,
                  let interval = Int32(intervalText),
                  interval > 0 else { return }
            
            ticker.commands = commands
            ticker.interval = Double(interval)
            ticker.lastModified = Date()
            
            do {
                try ticker.managedObjectContext?.save()
                self.loadTickers()
            } catch {
                self.showAlert(title: "Error", message: "Failed to update ticker: \\(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func toggleTicker(_ ticker: Ticker) {
        ticker.isEnabled.toggle()
        ticker.lastModified = Date()
        
        do {
            try ticker.managedObjectContext?.save()
            loadTickers()
        } catch {
            showAlert(title: "Error", message: "Failed to toggle ticker: \\(error.localizedDescription)")
        }
    }
    
    private func deleteTicker(_ ticker: Ticker) {
        let alert = UIAlertController(
            title: "Delete Ticker",
            message: "Are you sure you want to delete this ticker?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            let context = ticker.managedObjectContext!
            context.delete(ticker)
            
            do {
                try context.save()
                self.loadTickers()
            } catch {
                self.showAlert(title: "Error", message: "Failed to delete ticker: \\(error.localizedDescription)")
            }
        })
        
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - TickersListViewController Table View

extension TickersListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tickers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TickerCell", for: indexPath)
        let ticker = tickers[indexPath.row]
        
        cell.textLabel?.text = "Every \\(ticker.interval)s"
        cell.detailTextLabel?.text = ticker.commands ?? "No commands"
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cell.textLabel?.textColor = ticker.isEnabled ? ThemeManager.shared.currentTheme.fontColor : ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.5)
        cell.detailTextLabel?.textColor = ticker.isEnabled ? ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.7) : ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.3)
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let ticker = tickers[indexPath.row]
        
        let alert = UIAlertController(title: "Every \\(ticker.interval)s", message: "Choose an action", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Edit", style: .default) { [weak self] _ in
            self?.editTicker(ticker)
        })
        
        let toggleTitle = ticker.isEnabled ? "Disable" : "Enable"
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { [weak self] _ in
            self?.toggleTicker(ticker)
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteTicker(ticker)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return tickers.isEmpty ? nil : "\\(tickers.count) Ticker(s)"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return tickers.isEmpty ? "No tickers created yet. Tap + to add one." : "Tickers execute commands at regular intervals when connected."
    }
}
