import UIKit
import CoreData
import Foundation

// MARK: - Layout Constants (deprecated - use AppConstants.UI instead)

enum LayoutConstants {
    static let tabBarHeight: CGFloat = AppConstants.UI.tabBarHeight
    static let sideMenuWidth: CGFloat = AppConstants.UI.sideMenuWidth
    static let sideMenuSwipeActivationEdgeWidth: CGFloat = AppConstants.UI.sideMenuSwipeActivationEdgeWidth
    static let sideMenuOpenTranslationThreshold: CGFloat = AppConstants.UI.sideMenuOpenTranslationThreshold
    static let sideMenuDimAlpha: CGFloat = AppConstants.UI.sideMenuDimAlpha
}

// MARK: - Animation Constants (deprecated - use AppConstants.UI instead)

enum AnimationConstants {
    static let keyboardMaxDuration: Double = AppConstants.UI.keyboardMaxDuration
    static let sideMenuAnimationDuration: Double = AppConstants.UI.sideMenuAnimationDuration
    static let dragEndAnimationDuration: Double = AppConstants.UI.dragEndAnimationDuration
    static let tabBarLongPressDuration: Double = AppConstants.UI.tabBarLongPressDuration
}

// MARK: - Protocols

protocol WorldDisplayControllerDelegate: AnyObject {
    func worldDisplayController(_ controller: WorldDisplayController, didSelectWorld worldID: NSManagedObjectID)
    func worldDisplayControllerDidRequestNewWorld(_ controller: WorldDisplayController)
}

protocol ClientViewControllerDelegate: AnyObject {
    func clientDidConnect(_ client: ClientViewController)
    func clientDidDisconnect(_ client: ClientViewController)
    func clientDidReceiveText(_ client: ClientViewController)
    func clientDidRequestWorldSelection(_ client: ClientViewController)
    func clientViewControllerDidRequestSideMenu(_ controller: ClientViewController)
}

// MARK: - Session Status

struct SessionStatus {
    let isConnected: Bool
    let isLogging: Bool
    let automationCount: Int
    let hasActivity: Bool
}

// MARK: - ClientContainer

class ClientContainer: UIViewController {
    
    // MARK: - Properties
    
    private var activeClients: [NSManagedObjectID: ClientViewController] = [:]
    private var currentClientViewController: ClientViewController?
    private var worldDisplayController: WorldDisplayController?
    private var tabBar: DraggableTabBar!
    private var tabBarItems: [NSManagedObjectID: UITabBarItem] = [:]
    private var tabBaseImages: [NSManagedObjectID: UIImage] = [:]
    private var tabOrder: [NSManagedObjectID] = []
    private var tabBarBottomConstraint: NSLayoutConstraint!
    private var clientViewBottomConstraint: NSLayoutConstraint?
    private var keyboardManager: KeyboardManager?
    
    private var isShowingSideMenu = false
    private let sideMenuWidth: CGFloat = LayoutConstants.sideMenuWidth
    private var sideMenuLeadingConstraint: NSLayoutConstraint!
    

    
    // MARK: - Shared Instance
    
    private static var _sharedInstance: ClientContainer?
    
    static var shared: ClientContainer? {
        return _sharedInstance
    }
    
    static var worldDisplayDrawer: WorldDisplayController? {
        return shared?.worldDisplayController
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        ClientContainer._sharedInstance = self
        
        setupUI()
        setupNotifications()
        loadInitialWorld()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Apply current theme
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        // Setup tab bar
        setupTabBar()
        
        // Setup world display controller (side menu)
        worldDisplayController = WorldDisplayController()
        worldDisplayController?.delegate = self
        
        // Setup side menu
        setupSideMenu()
        
        // Setup gesture recognizers
        setupGestureRecognizers()
    }
    
    private func setupTabBar() {
        tabBar = DraggableTabBar()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = self
        tabBar.barTintColor = ThemeManager.shared.terminalBackgroundColor
        tabBar.tintColor = ThemeManager.shared.linkColor
        tabBar.unselectedItemTintColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.6)
        tabBar.dragDelegate = self
        
        // Add a border to make it more visible
        tabBar.layer.borderWidth = 0.5
        tabBar.layer.borderColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.3).cgColor
        
        // Ensure tab bar stays on top
        tabBar.layer.zPosition = 1000
        
        // Add long press gesture for customization mode (as fallback)
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleTabBarLongPress(_:)))
        longPressGesture.minimumPressDuration = AnimationConstants.tabBarLongPressDuration
        tabBar.addGestureRecognizer(longPressGesture)
        
        view.addSubview(tabBar)
        
        // Create the bottom constraint
        tabBarBottomConstraint = tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarBottomConstraint,
            tabBar.heightAnchor.constraint(equalToConstant: LayoutConstants.tabBarHeight)
        ])
        
        // Add "+" button for new connections (match icon size to session tabs)
        let addIcon = UIImage(systemName: "plus.circle")
        let resizedAddIcon = addIcon?.resized(to: CGSize(width: 22, height: 22))
        let addItem = UITabBarItem(title: "Add", image: resizedAddIcon, tag: -1)
        addItem.selectedImage = resizedAddIcon
        tabBar.items = [addItem]
    }
    
    private func setupSideMenu() {
        // Use WorldDisplayController as the side menu content
        guard let worldDisplayController = worldDisplayController else { return }
        
        // Add world display controller as child view controller
        addChild(worldDisplayController)
        view.addSubview(worldDisplayController.view)
        worldDisplayController.didMove(toParent: self)
        
        // Position side menu off-screen initially
        worldDisplayController.view.translatesAutoresizingMaskIntoConstraints = false
        sideMenuLeadingConstraint = worldDisplayController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -sideMenuWidth)
        
        NSLayoutConstraint.activate([
            sideMenuLeadingConstraint,
            worldDisplayController.view.topAnchor.constraint(equalTo: view.topAnchor),
            worldDisplayController.view.widthAnchor.constraint(equalToConstant: sideMenuWidth),
            worldDisplayController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    

    
    private func setupGestureRecognizers() {
        // Pan gesture for side menu - only from left edge
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
        
        // Tap gesture to close menu - only when menu is open
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGesture.delegate = self
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(worldChanged(_:)),
            name: .worldChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged(_:)),
            name: .themeDidChange,
            object: nil
        )

        // Observe vitals updates to refresh tab icons
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vitalsDidUpdate(_:)),
            name: .vitalsDidUpdate,
            object: nil
        )
        
        // Centralized keyboard handling
        keyboardManager = KeyboardManager(
            willShow: { [weak self] keyboardFrame, duration, curve in
                guard let self = self else { return }
                // Calculate the keyboard position in the view's coordinate system
                let keyboardTop = self.view.convert(keyboardFrame, from: nil).minY
                
                // Deactivate the current bottom constraint
                self.tabBarBottomConstraint.isActive = false
                
                // Position the tab bar just above the keyboard
                self.tabBarBottomConstraint = self.tabBar.bottomAnchor.constraint(equalTo: self.view.topAnchor, constant: keyboardTop)
                self.tabBarBottomConstraint.isActive = true
                
                // Ensure tab bar is visible and on top
                self.tabBar.isHidden = false
                self.view.bringSubviewToFront(self.tabBar)
                
                UIView.animate(withDuration: min(duration, AnimationConstants.keyboardMaxDuration), delay: 0, options: [UIView.AnimationOptions(rawValue: curve), .allowUserInteraction]) {
                    self.view.layoutIfNeeded()
                }
            },
            willHide: { [weak self] duration, curve in
                guard let self = self else { return }
                
                // Deactivate the current bottom constraint
                self.tabBarBottomConstraint.isActive = false
                
                // Create and activate a new constraint that positions the tab bar at the bottom of the safe area
                self.tabBarBottomConstraint = self.tabBar.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
                self.tabBarBottomConstraint.isActive = true
                
                UIView.animate(withDuration: min(duration, AnimationConstants.keyboardMaxDuration), delay: 0, options: [UIView.AnimationOptions(rawValue: curve), .allowUserInteraction]) {
                    self.view.layoutIfNeeded()
                }
            }
        )

    }

    @objc private func vitalsDidUpdate(_ note: Notification) {
        guard let worldID = note.object as? NSManagedObjectID else { return }
        guard let tabItem = tabBarItems[worldID], let base = tabBaseImages[worldID] else { return }
        if let vitals = SessionVitalsStore.shared.vitals(for: worldID) {
            let overlay = renderVitalsIcon(base: base, vitals: vitals)
            tabItem.image = overlay
            tabItem.selectedImage = overlay
        } else {
            tabItem.image = base
            tabItem.selectedImage = base
        }
    }
    
    // MARK: - World Management
    
    private func loadInitialWorld() {
        // Don't load any world by default - just show empty state
        loadEmptyClient()
    }
    
    private func loadWorld(_ worldID: NSManagedObjectID) {
        print("ClientContainer: Loading world with ID: \(worldID)")
        
        // Check if this world is already open
        if let existingClient = activeClients[worldID] {
            print("ClientContainer: World already open, switching to it")
            switchToClient(existingClient, worldID: worldID)
            return
        }
        
        // Validate the world object ID and load the world safely
        let context = PersistenceController.shared.viewContext
        
        // Check if the object exists and is valid
        guard let world = try? context.existingObject(with: worldID) as? World else {
            print("ClientContainer: World object not found or invalid")
            return
        }
        
        // Verify the world is not deleted and not hidden
        if world.isDeleted || world.isHidden {
            print("ClientContainer: World is deleted or hidden")
            return
        }
        
        print("ClientContainer: Successfully loaded world: \(world.name ?? "Unknown")")
        
        // Create new client for world
        let clientViewController = ClientViewController.client(with: worldID)
        clientViewController.delegate = self
        
        // Add to active clients
        activeClients[worldID] = clientViewController
        
        // Add tab bar item
        addTabForWorld(world, worldID: worldID)
        
        // Switch to this client
        switchToClient(clientViewController, worldID: worldID)
        
        // Auto-connect when world is manually selected (regardless of startup preference)
        clientViewController.connect()
        
        // Update tab appearance
        updateTabForClient(clientViewController, connected: false)
        
        print("ClientContainer: World loaded successfully")
    }
    
    private func addTabForWorld(_ world: World, worldID: NSManagedObjectID) {
        // Use a clean, transparent base so vitals rings are not obstructed by any symbol
        let baseIcon = makeBaseTabImage(size: CGSize(width: 26, height: 26))
        
        let tabItem = UITabBarItem(
            title: world.name ?? "Unknown",
            image: baseIcon,
            tag: worldID.hashValue
        )
        tabItem.selectedImage = baseIcon
        
        tabBarItems[worldID] = tabItem
        tabBaseImages[worldID] = baseIcon
        tabOrder.append(worldID)
        updateTabBarItems()
    }
    
    private func updateTabBarItems() {
        var items: [UITabBarItem] = []
        
        // Add items in the stored order
        for worldID in tabOrder {
            if let tabItem = tabBarItems[worldID] {
                items.append(tabItem)
            }
        }
        
        // Add the "Add" button at the end (match icon size to session tabs)
        let addIcon = UIImage(systemName: "plus.circle")
        let resizedAddIcon = addIcon?.resized(to: CGSize(width: 22, height: 22))
        let addItem = UITabBarItem(title: "Add", image: resizedAddIcon, tag: -1)
        addItem.selectedImage = resizedAddIcon
        items.append(addItem)
        
        tabBar.items = items

        // Re-apply vitals overlay icons for all sessions
        refreshAllTabIcons()
    }

    private func refreshAllTabIcons() {
        for (worldID, tabItem) in tabBarItems {
            guard let base = tabBaseImages[worldID] else { continue }
            if let vitals = SessionVitalsStore.shared.vitals(for: worldID) {
                let overlay = renderVitalsIcon(base: base, vitals: vitals)
                tabItem.image = overlay
                tabItem.selectedImage = overlay
            } else {
                tabItem.image = base
                tabItem.selectedImage = base
            }
        }
    }

    private func renderVitalsIcon(base: UIImage, vitals: SessionVitalsStore.Vitals) -> UIImage {
        let size = base.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))
            let center = CGPoint(x: size.width/2, y: size.height/2)
            // Use thicker rings and keep strokes fully inside bounds
            let ringWidth: CGFloat = 3.0
            let halfW = ringWidth / 2
            let edgeInset: CGFloat = 0.5
            let maxRadius = min(size.width, size.height)/2 - edgeInset
            let outerRadius = maxRadius - halfW
            let innerRadius = outerRadius - ringWidth - 2.0 // 2pt gap between rings

            // Colors / state
            let isStale = Date().timeIntervalSince(vitals.updatedAt) > 10
            // Higher-contrast track to be visible on both light/dark themes
            // Use high-contrast track with subtle outer glow to ensure visibility
            let trackColor = ThemeManager.shared.isDarkTheme
                ? UIColor.white.withAlphaComponent(0.28)
                : UIColor.black.withAlphaComponent(0.34)
            func hpColor(for p: Double) -> UIColor {
                let hpGreen = Double((UserDefaults.standard.string(forKey: "Vitals.HP.GreenThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(Int.init) ?? 60) / 100.0
                let hpYellow = Double((UserDefaults.standard.string(forKey: "Vitals.HP.YellowThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(Int.init) ?? 30) / 100.0
                if p >= hpGreen { return .systemGreen }
                if p >= hpYellow { return .systemYellow }
                return .systemRed
            }

            // Outer HP ring
            ctx.cgContext.setLineWidth(ringWidth)
            ctx.cgContext.setLineCap(.round)
            // Outer faint halo
            ctx.cgContext.saveGState()
            ctx.cgContext.setShadow(offset: .zero, blur: 1.2, color: trackColor.withAlphaComponent(0.6).cgColor)
            // Track
            ctx.cgContext.setStrokeColor(trackColor.cgColor)
            ctx.cgContext.addArc(center: center, radius: outerRadius, startAngle: -.pi/2, endAngle: 1.5 * .pi, clockwise: false)
            ctx.cgContext.strokePath()
            ctx.cgContext.restoreGState()
            // Progress (HP)
            if let hpP = vitals.hpPercent {
                let end = (-.pi/2) + (2 * .pi * CGFloat(max(0,min(1,hpP))))
                let ringColor = hpColor(for: hpP)
                let stroke = isStale ? ringColor.withAlphaComponent(0.4) : ringColor
                ctx.cgContext.setStrokeColor(stroke.cgColor)
                ctx.cgContext.addArc(center: center, radius: outerRadius, startAngle: -.pi/2, endAngle: end, clockwise: false)
                ctx.cgContext.strokePath()
            }

            // Inner Mana ring
            ctx.cgContext.setStrokeColor(trackColor.cgColor)
            ctx.cgContext.setLineWidth(ringWidth)
            ctx.cgContext.addArc(center: center, radius: innerRadius, startAngle: -.pi/2, endAngle: 1.5 * .pi, clockwise: false)
            ctx.cgContext.strokePath()
            // Progress (Mana)
            if let p = vitals.manaPercent {
                let end = (-.pi/2) + (2 * .pi * CGFloat(max(0,min(1,p))))
                let mnGreenOpt = UserDefaults.standard.string(forKey: "Vitals.Mana.GreenThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let mnYellowOpt = UserDefaults.standard.string(forKey: "Vitals.Mana.YellowThresholdPercent")?.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasMnThresholds = (Int(mnGreenOpt ?? "") != nil) && (Int(mnYellowOpt ?? "") != nil)
                let baseColor: UIColor = {
                    guard hasMnThresholds else { return .systemBlue }
                    let green = Double(Int(mnGreenOpt!) ?? 60) / 100.0
                    let yellow = Double(Int(mnYellowOpt!) ?? 30) / 100.0
                    if p >= green { return .systemGreen }
                    if p >= yellow { return .systemYellow }
                    return .systemRed
                }()
                let stroke = isStale ? baseColor.withAlphaComponent(0.4) : baseColor
                ctx.cgContext.setStrokeColor(stroke.cgColor)
                ctx.cgContext.addArc(center: center, radius: innerRadius, startAngle: -.pi/2, endAngle: end, clockwise: false)
                ctx.cgContext.strokePath()
            }
        }
        return img.withRenderingMode(.alwaysOriginal)
    }

    // Create a transparent base image with slight border for contrast
    private func makeBaseTabImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            // Clear background
            UIColor.clear.setFill()
            ctx.fill(rect)
            // Optional subtle outline to help rings stand on any theme
            let outlineRect = rect.insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(ovalIn: outlineRect)
            ThemeManager.shared.terminalTextColor.withAlphaComponent(0.12).setStroke()
            path.lineWidth = 1
            path.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }
    
    private func switchToClient(_ client: ClientViewController, worldID: NSManagedObjectID) {
        // Capture whether keyboard is currently shown for the active session
        let shouldKeepKeyboardFocused = currentClientViewController?.isInputFocused() ?? false

        // Add the new client FIRST so we can transfer first responder without dismissing the keyboard
        addChild(client)
        view.addSubview(client.view)

        // Set up constraints
        client.view.translatesAutoresizingMaskIntoConstraints = false
        clientViewBottomConstraint = client.view.bottomAnchor.constraint(equalTo: tabBar.topAnchor)

        NSLayoutConstraint.activate([
            client.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            client.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            client.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clientViewBottomConstraint!
        ])

        client.didMove(toParent: self)
        client.view.alpha = 1.0

        // If input was focused, immediately make the new input first responder BEFORE removing the old view
        if shouldKeepKeyboardFocused {
            client.focusInput()
        }

        // Now safely remove the previous client so the keyboard never dismisses between views
        if let previous = currentClientViewController {
            previous.view.alpha = 1.0
            previous.view.removeFromSuperview()
            previous.removeFromParent()
        }

        // Remove any welcome label
        view.subviews.forEach { subview in
            if subview.tag == 999 { subview.removeFromSuperview() }
        }

        currentClientViewController = client

        // Update navigation bar with close button
        setupNavigationBarForWorld()

        // Update tab selection
        if let tabItem = tabBarItems[worldID] {
            tabBar.selectedItem = tabItem
        }

        // Update vitals overlays for all tabs now that active tab changed
        refreshAllTabIcons()
    }
    
    private func setupNavigationBarForWorld() {
        // Create close button
        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark.circle"),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        closeButton.accessibilityLabel = "Close World"
        
        // Add to navigation bar (left side, next to menu button)
        var leftItems = navigationItem.leftBarButtonItems ?? []
        
        // Remove any existing close button
        leftItems.removeAll { $0.accessibilityLabel == "Close World" }
        
        // Add close button
        leftItems.append(closeButton)
        navigationItem.leftBarButtonItems = leftItems
    }
    
    @objc private func closeButtonTapped() {
        showCloseWorldOptions()
    }
    
    private func closeWorld(_ worldID: NSManagedObjectID) {
        // Disconnect and remove the client
        if let client = activeClients[worldID] {
            let wasCurrent = (currentClientViewController === client)
            client.disconnect()
            client.view.removeFromSuperview()
            client.removeFromParent()
            
            // Remove from tracking
            activeClients.removeValue(forKey: worldID)
            tabBarItems.removeValue(forKey: worldID)
            tabOrder.removeAll { $0 == worldID }
            
            // Update tab bar
            updateTabBarItems()
            
            // If this was the current client, switch to another or show empty state
            if wasCurrent {
                currentClientViewController = nil
                if let (firstWorldID, firstClient) = activeClients.first {
                    switchToClient(firstClient, worldID: firstWorldID)
                } else {
                    // No more clients, show empty state
                    showEmptyState()
                }
            }
            
            print("ClientContainer: Closed world: \(worldID)")
            return
        }
        
        // If we didn't find the client by ID, just ensure tracking structures are clean
        activeClients.removeValue(forKey: worldID)
        tabBarItems.removeValue(forKey: worldID)
        tabOrder.removeAll { $0 == worldID }
        updateTabBarItems()
    }
    
    private func showEmptyState() {
        // Remove any current client view
        currentClientViewController?.view.removeFromSuperview()
        currentClientViewController?.removeFromParent()
        currentClientViewController = nil
        
        // Remove close button from navigation bar
        var leftItems = navigationItem.leftBarButtonItems ?? []
        leftItems.removeAll { $0.accessibilityLabel == "Close World" }
        navigationItem.leftBarButtonItems = leftItems.isEmpty ? nil : leftItems
        
        // Clear tab selection
        tabBar.selectedItem = nil
        
        // Show welcome message or instructions
        let welcomeLabel = UILabel()
        welcomeLabel.text = "Select a world from the menu to begin"
        welcomeLabel.textAlignment = .center
        welcomeLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.6)
        welcomeLabel.font = UIFont.systemFont(ofSize: 18)
        welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(welcomeLabel)
        NSLayoutConstraint.activate([
            welcomeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            welcomeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // Remove the welcome label after a delay or when a new world is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Tag it so we can remove it later
            welcomeLabel.tag = 999
        }
    }
    
    private func loadEmptyClient() {
        // Remove current client if any
        if let currentClient = currentClientViewController {
            currentClient.view.isHidden = true
        }
        
        // Only create empty client if no active clients exist
        if activeClients.isEmpty {
            // Create empty client
            let emptyClient = ClientViewController.client()
            emptyClient.delegate = self
            
            addChild(emptyClient)
            view.addSubview(emptyClient.view)
            emptyClient.didMove(toParent: self)
            
            // Position client view (above tab bar)
            emptyClient.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                emptyClient.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                emptyClient.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                emptyClient.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                emptyClient.view.bottomAnchor.constraint(equalTo: tabBar.topAnchor)
            ])
            
            currentClientViewController = emptyClient
        }
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        
        switch gesture.state {
        case .began:
            break
        case .changed:
            if !isShowingSideMenu && translation.x > 0 && translation.x < LayoutConstants.sideMenuWidth {
                // Opening gesture
                let progress = min(translation.x / LayoutConstants.sideMenuWidth, 1.0)
                sideMenuLeadingConstraint.constant = -sideMenuWidth + (sideMenuWidth * progress)
                view.layoutIfNeeded()
                let dimDelta = 1.0 - LayoutConstants.sideMenuDimAlpha
                currentClientViewController?.view.alpha = 1.0 - (dimDelta * progress)
            } else if isShowingSideMenu && translation.x < 0 {
                // Closing gesture
                let progress = min(-translation.x / LayoutConstants.sideMenuWidth, 1.0)
                sideMenuLeadingConstraint.constant = -(sideMenuWidth * progress)
                view.layoutIfNeeded()
                let dimDelta = 1.0 - LayoutConstants.sideMenuDimAlpha
                currentClientViewController?.view.alpha = LayoutConstants.sideMenuDimAlpha + (dimDelta * progress)
            }
        case .ended, .cancelled:
            if velocity.x > 500 || translation.x > LayoutConstants.sideMenuOpenTranslationThreshold {
                openSideMenu()
            } else if velocity.x < -500 || translation.x < -LayoutConstants.sideMenuOpenTranslationThreshold {
                closeSideMenu()
            } else {
                // Snap back to current state
                if isShowingSideMenu {
                    openSideMenu()
                } else {
                    closeSideMenu()
                }
            }
        default:
            break
        }
    }
    
    @objc private func handleTapGesture(_ gesture: UITapGestureRecognizer) {
        if isShowingSideMenu {
            closeSideMenu()
        }
    }
    
    @objc private func handleTabBarLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        
        let location = gesture.location(in: tabBar)
        if let tabBarItem = tabBar.items?.first(where: { item in
            guard let view = tabBar.subviews.first(where: { $0.frame.contains(location) }) else { return false }
            return view.tag == item.tag
        }), tabBarItem.tag != -1 {
            // Start customization mode
            tabBar.beginCustomizingItems(tabBar.items ?? [])
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func worldChanged(_ notification: Notification) {
        guard let worldID = notification.object as? NSManagedObjectID else { return }
        
        DispatchQueue.main.async {
            self.loadWorld(worldID)
            self.closeSideMenu()
        }
    }
    
    @objc private func themeChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            self.tabBar.barTintColor = ThemeManager.shared.terminalBackgroundColor
            self.tabBar.tintColor = ThemeManager.shared.linkColor
            self.tabBar.unselectedItemTintColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.6)
        }
    }
    
    private func updateTabTitle(for worldID: NSManagedObjectID, connected: Bool) {
        guard let tabItem = tabBarItems[worldID],
              let client = activeClients[worldID] else { return }
        
        let context = PersistenceController.shared.viewContext
        guard let world = try? context.existingObject(with: worldID) as? World else { return }
        
        let worldName = world.name ?? "Unknown"
        let status = getSessionStatus(for: client, world: world)
        
        // Update title with status indicators
        tabItem.title = formatTabTitle(worldName: worldName, status: status)
        
        // Do not change the tab icon; keep a clean base so vitals rings are unobstructed
        // Re-apply overlays after any title/status change
        refreshAllTabIcons()
        
        // Update badge if needed
        updateTabBadge(tabItem: tabItem, status: status)
    }
    
    private func getSessionStatus(for client: ClientViewController, world: World) -> SessionStatus {
        let isConnected = client.isConnected
        let isLogging = client.sessionLogger.isLogging
        let automationCount = getAutomationCount(for: world)
        
        return SessionStatus(
            isConnected: isConnected,
            isLogging: isLogging,
            automationCount: automationCount,
            hasActivity: false // Can be enhanced later with activity tracking
        )
    }
    
    private func getAutomationCount(for world: World) -> Int {
        let triggers = Array(world.triggers ?? []).filter { !$0.isHidden && $0.isActive }.count
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.count
        let tickers = Array(world.tickers ?? []).filter { !$0.isHidden && $0.isEnabled }.count
        return triggers + aliases + tickers
    }
    
    private func formatTabTitle(worldName: String, status: SessionStatus) -> String {
        var indicators: [String] = []
        
        // Connection status
        if status.isConnected {
            indicators.append("🟢")
        }
        
        // Logging status
        if status.isLogging {
            indicators.append("📝")
        }
        
        // Automation indicators
        if status.automationCount > 0 {
            indicators.append("🤖")
        }
        
        // Activity indicator (for future use)
        if status.hasActivity {
            indicators.append("💬")
        }
        
        let prefix = indicators.isEmpty ? "" : indicators.joined() + " "
        return "\(prefix)\(worldName)"
    }
    
    private func getTabIcon(for status: SessionStatus) -> String {
        switch (status.isConnected, status.automationCount > 0) {
        case (true, true):
            return "globe.badge.chevron.backward"  // Connected with automation
        case (true, false):
            return "globe.americas"                // Connected without automation
        case (false, true):
            return "globe.badge.chevron.backward"  // Disconnected with automation
        case (false, false):
            return "globe"                         // Disconnected without automation
        }
    }
    
    private func updateTabBadge(tabItem: UITabBarItem, status: SessionStatus) {
        // Show automation count as badge if significant
        if status.automationCount > 5 {
            tabItem.badgeValue = "\(status.automationCount)"
            tabItem.badgeColor = status.isConnected ? .systemGreen : .systemOrange
        } else {
            tabItem.badgeValue = nil
        }
    }
    
    private func updateTabForClient(_ client: ClientViewController, connected: Bool) {
        // Find the world ID for this client
        for (worldID, activeClient) in activeClients {
            if activeClient == client {
                updateTabTitle(for: worldID, connected: connected)
                break
            }
        }
    }
    
    func refreshTabStatus(for client: ClientViewController) {
        // Find the world ID for this client and refresh its tab status
        for (worldID, activeClient) in activeClients {
            if activeClient == client {
                updateTabTitle(for: worldID, connected: client.isConnected)
                break
            }
        }
    }
    
    func refreshAllTabStatuses() {
        // Refresh all tab statuses
        for (worldID, client) in activeClients {
            updateTabTitle(for: worldID, connected: client.isConnected)
        }
    }
    
    private func getCurrentClient() -> ClientViewController? {
        return currentClientViewController
    }
    
    // MARK: - Side Menu Management
    
    func toggleSideMenu(animated: Bool = true) {
        if isShowingSideMenu {
            closeSideMenu(animated: animated)
        } else {
            openSideMenu(animated: animated)
        }
    }
    
    func openSideMenu(animated: Bool = true) {
        guard !isShowingSideMenu, let worldDisplayController = worldDisplayController else { return }
        
        print("ClientContainer: Opening side menu")
        isShowingSideMenu = true
        
        // Ensure the side menu is brought to front and user interaction is enabled
        view.bringSubviewToFront(worldDisplayController.view)
        worldDisplayController.view.isUserInteractionEnabled = true
        
        let duration = animated ? AnimationConstants.sideMenuAnimationDuration : 0.0
        
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut) {
            self.sideMenuLeadingConstraint.constant = 0
            self.view.layoutIfNeeded()
            
            // Dim the main content
            self.currentClientViewController?.view.alpha = 0.7
        }
    }
    
    func closeSideMenu(animated: Bool = true) {
        guard isShowingSideMenu else { return }
        
        isShowingSideMenu = false
        
        let duration = animated ? AnimationConstants.sideMenuAnimationDuration : 0.0
        
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut) {
            self.sideMenuLeadingConstraint.constant = -self.sideMenuWidth
            self.view.layoutIfNeeded()
            
            // Restore main content alpha for current client
            self.currentClientViewController?.view.alpha = 1.0
        } completion: { _ in
            // Ensure all active client views have full alpha (in case of view switching during animation)
            for client in self.activeClients.values {
                client.view.alpha = 1.0
            }
        }
    }
    

    
    
    // MARK: - App State Handling
    
    func handleAppStateChange(_ notificationName: Notification.Name) {
        print("ClientContainer: Handling app state change: \(notificationName)")
        
        // Forward app state changes to all active clients
        for client in activeClients.values {
            client.handleAppStateChange(notificationName)
        }
    }
    
    // MARK: - Public Session Management (for SessionDashboardViewController)
    
    func isWorldConnected(_ worldID: NSManagedObjectID) -> Bool {
        return activeClients[worldID]?.isConnected ?? false
    }
    
    func connectToWorld(_ worldID: NSManagedObjectID) {
        if let client = activeClients[worldID] {
            client.connect()
        } else {
            loadWorld(worldID)
            activeClients[worldID]?.connect()
        }
    }
    
    func disconnectWorld(_ worldID: NSManagedObjectID) {
        activeClients[worldID]?.disconnect()
    }
    
    func switchToWorld(_ worldID: NSManagedObjectID) {
        if let client = activeClients[worldID] {
            switchToClient(client, worldID: worldID)
        }
    }
}

// MARK: - WorldDisplayControllerDelegate

extension ClientContainer: WorldDisplayControllerDelegate {
    func worldDisplayController(_ controller: WorldDisplayController, didSelectWorld worldID: NSManagedObjectID) {
        print("ClientContainer: World selected, validating and loading world")
        
        // Validate the world ID before attempting to load
        let context = PersistenceController.shared.viewContext
        
        // Check if the world exists and is accessible
        guard let world = try? context.existingObject(with: worldID) as? World else {
            print("ClientContainer: Selected world is not accessible")
            return
        }
        
        if world.isDeleted || world.isHidden {
            print("ClientContainer: Selected world is deleted or hidden")
            return
        }
        
        print("ClientContainer: Loading valid world: \(world.name ?? "Unknown")")
        loadWorld(worldID)
        closeSideMenu()
    }
    
    func worldDisplayControllerDidRequestNewWorld(_ controller: WorldDisplayController) {
        print("ClientContainer: New world requested")
        closeSideMenu()
        
        // Create a simple alert-based world creation form
        let alert = UIAlertController(title: "Create New World", message: "Enter world details", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "World Name"
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Hostname"
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Port"
            textField.keyboardType = .numberPad
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text, !name.isEmpty,
                  let hostname = alert.textFields?[1].text, !hostname.isEmpty,
                  let portText = alert.textFields?[2].text, !portText.isEmpty,
                  let port = Int32(portText) else {
                return
            }
            
            let context = PersistenceController.shared.container.viewContext
            
            // Check for duplicate world names
            let namePredicate = NSPredicate(format: "name == %@ AND isHidden == NO", name)
            let nameRequest: NSFetchRequest<World> = World.fetchRequest()
            nameRequest.predicate = namePredicate
            
            do {
                let existingWorlds = try context.fetch(nameRequest)
                if !existingWorlds.isEmpty {
                    // Show error for duplicate name
                    let errorAlert = UIAlertController(title: "Duplicate World Name", message: "A world with the name '\(name)' already exists. Please choose a different name.", preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(errorAlert, animated: true)
                    return
                }
                
                // Create new world (allow duplicate hostnames)
                let world = World(context: context)
                world.name = name
                world.hostname = hostname
                world.port = port
                world.lastModified = Date()
                
                try context.save()
                // Load the newly created world
                self?.loadWorld(world.objectID)
            } catch {
                print("Failed to save new world: \(error)")
            }
        })
        
        present(alert, animated: true)
    }
}

// MARK: - ClientViewControllerDelegate

extension ClientContainer: ClientViewControllerDelegate {
    func clientDidConnect(_ client: ClientViewController) {
        // Find the world ID for this client
        for (worldID, activeClient) in activeClients {
            if activeClient == client {
                updateTabTitle(for: worldID, connected: true)
                break
            }
        }
    }
    
    func clientDidDisconnect(_ client: ClientViewController) {
        // Find the world ID for this client
        for (worldID, activeClient) in activeClients {
            if activeClient == client {
                updateTabTitle(for: worldID, connected: false)
                break
            }
        }
    }
    
    func clientDidReceiveText(_ client: ClientViewController) {
        // Could add notification badges or other indicators here
    }
    
    func clientDidRequestWorldSelection(_ client: ClientViewController) {
        openSideMenu()
    }
    
    func clientViewControllerDidRequestSideMenu(_ controller: ClientViewController) {
        openSideMenu()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ClientContainer: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let touchPoint = touch.location(in: view)
        
        // Don't interfere with touches on the MudView (for long press line selection)
        if let touchView = touch.view, touchView.isDescendant(of: currentClientViewController?.view ?? UIView()) {
            // Allow taps on the dimmed client area to close the side menu when it's open
            if gestureRecognizer is UITapGestureRecognizer {
                if isShowingSideMenu {
                    // Defer to the tap handler below to decide if tap is outside the menu
                } else {
                    return false
                }
            }
        }
        
        // Handle tap gesture
        if gestureRecognizer is UITapGestureRecognizer {
            // Only handle tap when side menu is showing and touch is outside the side menu
            if isShowingSideMenu {
                if let sideMenuView = worldDisplayController?.view {
                    return !sideMenuView.frame.contains(touchPoint)
                }
            }
            return false
        }
        
        // Handle pan gesture
        if gestureRecognizer is UIPanGestureRecognizer {
            // When side menu is open, only handle pan gestures outside the menu
            if isShowingSideMenu {
                if let sideMenuView = worldDisplayController?.view {
                    return !sideMenuView.frame.contains(touchPoint)
                }
            }
            
            // When side menu is closed, only handle pan gestures from the left edge
            if !isShowingSideMenu {
                return touchPoint.x < LayoutConstants.sideMenuSwipeActivationEdgeWidth // Only respond to touches near the left edge
            }
        }
        
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow long press gestures to work simultaneously (for MudView line selection)
        if otherGestureRecognizer is UILongPressGestureRecognizer {
            return true
        }
        
        // Allow table view gestures to work when side menu is open
        return false
    }
}

// MARK: - UITabBarDelegate

extension ClientContainer: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        if item.tag == -1 {
            // "Add" button tapped
            openSideMenu()
        } else {
            // Find the world ID for this tab
            for (worldID, tabItem) in tabBarItems {
                if tabItem == item {
                    if let client = activeClients[worldID] {
                        switchToClient(client, worldID: worldID)
                    }
                    break
                }
            }
        }
    }
    
    func tabBar(_ tabBar: UITabBar, didBeginCustomizing items: [UITabBarItem]) {
        // Built-in customization mode started - disable drag gestures to avoid conflicts
        if let draggableTabBar = tabBar as? DraggableTabBar {
            draggableTabBar.dragGesture.isEnabled = false
        }
    }
    
    func tabBar(_ tabBar: UITabBar, didEndCustomizing items: [UITabBarItem], changed: Bool) {
        // Re-enable drag gestures
        if let draggableTabBar = tabBar as? DraggableTabBar {
            draggableTabBar.dragGesture.isEnabled = true
        }
        
        if changed {
            // Update tab order based on new arrangement
            var newOrder: [NSManagedObjectID] = []
            for item in items {
                if item.tag != -1 { // Skip the "Add" button
                    for (worldID, tabItem) in tabBarItems {
                        if tabItem == item {
                            newOrder.append(worldID)
                            break
                        }
                    }
                }
            }
            tabOrder = newOrder
            updateTabBarItems()
        }
    }
    
    func tabBar(_ tabBar: UITabBar, shouldSelect item: UITabBarItem) -> Bool {
        return true
    }
    
    // Add method to show close world options
    func showCloseWorldOptions() {
        guard let currentClient = currentClientViewController,
              let currentWorldID = getCurrentWorldID() else { return }
        
        let context = PersistenceController.shared.viewContext
        guard let world = try? context.existingObject(with: currentWorldID) as? World else { return }
        
        let alert = UIAlertController(
            title: "Close World",
            message: "What would you like to do with \(world.name ?? "Unknown")?",
            preferredStyle: .actionSheet
        )
        
        // Disconnect but keep tab
        alert.addAction(UIAlertAction(title: "Disconnect", style: .default) { _ in
            currentClient.disconnect()
        })
        
        // Close tab completely
        alert.addAction(UIAlertAction(title: "Close Tab", style: .destructive) { [weak self] _ in
            self?.closeWorld(currentWorldID)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    private func getCurrentWorldID() -> NSManagedObjectID? {
        guard let currentClient = currentClientViewController else { return nil }
        
        // Find the world ID for the current client
        for (worldID, client) in activeClients {
            if client == currentClient {
                return worldID
            }
        }
        return nil
    }
    
    // MARK: - Multi-Session Command Support
    
    func sendCommandToAllSessions(_ command: String) -> Int {
        var sentCount = 0
        
        for (_, client) in activeClients {
            if client.isConnected {
                client.sendDirectCommand(command)
                sentCount += 1
            }
        }
        
        return sentCount
    }
    
    func sendCommandToSession(named sessionName: String, command: String) -> Bool {
        let context = PersistenceController.shared.viewContext
        
        for (worldID, client) in activeClients {
            guard let world = try? context.existingObject(with: worldID) as? World else { continue }
            
            if let worldName = world.name,
               worldName.lowercased() == sessionName.lowercased(),
               client.isConnected {
                client.sendDirectCommand(command)
                return true
            }
        }
        
        return false
    }
    
    func getAvailableSessionNames() -> [String] {
        let context = PersistenceController.shared.viewContext
        var sessionNames: [String] = []
        
        for (worldID, client) in activeClients {
            guard let world = try? context.existingObject(with: worldID) as? World else { continue }
            
            if let worldName = world.name, client.isConnected {
                sessionNames.append(worldName)
            }
        }
        
        return sessionNames.sorted()
    }
}

// MARK: - DraggableTabBarDelegate

extension ClientContainer: DraggableTabBarDelegate {
    func tabBar(_ tabBar: DraggableTabBar, didReorderItems items: [UITabBarItem]) {
        // Update tab order based on new arrangement
        var newOrder: [NSManagedObjectID] = []
        for item in items {
            if item.tag != -1 { // Skip the "Add" button
                for (worldID, tabItem) in tabBarItems {
                    if tabItem == item {
                        newOrder.append(worldID)
                        break
                    }
                }
            }
        }
        tabOrder = newOrder
        updateTabBarItems()
    }
}

// MARK: - DraggableTabBar

class DraggableTabBar: UITabBar {
    weak var dragDelegate: DraggableTabBarDelegate?
    var dragGesture: UIPanGestureRecognizer!
    private var draggedItem: UITabBarItem?
    private var originalItems: [UITabBarItem]?
    private var draggedView: UIView?
    private var dragOffset: CGPoint = .zero
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupDragGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDragGesture()
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var sizeThatFits = super.sizeThatFits(size)
        sizeThatFits.height = LayoutConstants.tabBarHeight
        return sizeThatFits
    }
    
    private func setupDragGesture() {
        dragGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        dragGesture.delegate = self
        addGestureRecognizer(dragGesture)
    }
    
    @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            guard let item = itemAt(location), item.tag != -1 else { return }
            draggedItem = item
            originalItems = items
            
            // Create a snapshot of the dragged item with enhanced visual feedback
            if let itemView = viewForItem(item) {
                draggedView = itemView.snapshotView(afterScreenUpdates: true)
                if let draggedView = draggedView {
                    draggedView.frame = itemView.frame
                    draggedView.alpha = 0.8
                    draggedView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                    draggedView.layer.shadowColor = UIColor.black.cgColor
                    draggedView.layer.shadowOffset = CGSize(width: 0, height: 2)
                    draggedView.layer.shadowOpacity = 0.3
                    draggedView.layer.shadowRadius = 4
                    addSubview(draggedView)
                    
                    dragOffset = CGPoint(
                        x: location.x - itemView.center.x,
                        y: location.y - itemView.center.y
                    )
                    
                    // Dim the original item
                    itemView.alpha = 0.3
                }
            }
            
        case .changed:
            guard let draggedView = draggedView else { return }
            draggedView.center = CGPoint(
                x: location.x - dragOffset.x,
                y: location.y - dragOffset.y
            )
            
            // Check if we should swap items (but not with the Add button)
            if let newItem = itemAt(location), 
               newItem != draggedItem, 
               newItem.tag != -1 { // Don't allow swapping with Add button
                swapItems(draggedItem, with: newItem)
            }
            
        case .ended, .cancelled:
            // Restore original item alpha
            if let draggedItem = draggedItem, let itemView = viewForItem(draggedItem) {
                itemView.alpha = 1.0
            }
            
            // Animate drag view removal
            if let draggedView = draggedView {
                UIView.animate(withDuration: 0.2, animations: {
                    draggedView.alpha = 0
                    draggedView.transform = .identity
                }) { _ in
                    draggedView.removeFromSuperview()
                }
            }
            
            draggedView = nil
            draggedItem = nil
            originalItems = nil
            
            // Notify delegate of reordering
            if let items = items {
                dragDelegate?.tabBar(self, didReorderItems: items)
            }
            
        default:
            break
        }
    }
    
    private func itemAt(_ point: CGPoint) -> UITabBarItem? {
        guard let items = items else { return nil }
        
        // Calculate tab width based on available space
        let tabWidth = bounds.width / CGFloat(items.count)
        
        for (index, item) in items.enumerated() {
            let tabFrame = CGRect(x: CGFloat(index) * tabWidth, y: 0, width: tabWidth, height: bounds.height)
            if tabFrame.contains(point) {
                return item
            }
        }
        return nil
    }
    
    private func viewForItem(_ item: UITabBarItem) -> UIView? {
        guard let items = items, let index = items.firstIndex(of: item) else { return nil }
        
        // Calculate tab frame based on index
        let tabWidth = bounds.width / CGFloat(items.count)
        let tabFrame = CGRect(x: CGFloat(index) * tabWidth, y: 0, width: tabWidth, height: bounds.height)
        
        // Find the subview that contains this frame
        return subviews.first { subview in
            return subview.frame.intersects(tabFrame) && subview.frame.width > 0
        }
    }
    
    private func swapItems(_ item1: UITabBarItem?, with item2: UITabBarItem?) {
        guard let item1 = item1, let item2 = item2,
              let items = items,
              let index1 = items.firstIndex(of: item1),
              let index2 = items.firstIndex(of: item2) else { return }
        
        var newItems = items
        newItems.swapAt(index1, index2)
        self.items = newItems
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DraggableTabBar: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: self)
        if let item = itemAt(location), item.tag != -1 {
            return true
        }
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow simultaneous recognition with other gestures
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Prioritize drag gestures over taps for better UX
        return gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer
    }
}

// MARK: - DraggableTabBarDelegate

protocol DraggableTabBarDelegate: AnyObject {
    func tabBar(_ tabBar: DraggableTabBar, didReorderItems items: [UITabBarItem])
}

// MARK: - UIImage Extension

extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        defer { UIGraphicsEndImageContext() }
        
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
} 