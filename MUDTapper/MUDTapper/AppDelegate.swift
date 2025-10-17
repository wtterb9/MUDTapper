import UIKit
import CoreData
import UserNotifications
import BackgroundTasks

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    var notificationObserver: NotificationManager?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Setup Core Data
        setupCoreData()
        
        // Create default worlds if necessary
        World.createDefaultWorldsIfNecessary()
        
        // Setup themes
        ThemeManager.shared.setupAppearance()
        
        // Setup window and root view controller
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ClientContainer()
        window?.makeKeyAndVisible()
        
        // Setup notification observer
        notificationObserver = NotificationManager()
        
        // Disable idle timer for MUD gaming
        application.isIdleTimerDisabled = true
        
        // Disable shake to edit
        application.applicationSupportsShakeToEdit = false
        
        // Setup default user preferences
        setupDefaultUserDefaults()
        
        // Migrate passwords from Core Data to Keychain (one-time migration)
        migratePasswordsIfNeeded()
        
        // Register for app state notifications
        setupAppStateNotifications()
        
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        guard let host = url.host, url.scheme == "telnet" else {
            return false
        }
        
        let context = PersistenceController.shared.viewContext
        let port = url.port ?? 23
        
        // Check if this exact world already exists (hostname + port)
        let predicate = NSPredicate(format: "hostname == %@ AND port == %d AND isHidden == NO", host.lowercased(), Int32(port))
        let request: NSFetchRequest<World> = World.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \World.name, ascending: true)]
        
        do {
            let existingWorlds = try context.fetch(request)
            
            if let existing = existingWorlds.first {
                // Post notification for existing world
                NotificationCenter.default.post(name: .worldChanged, object: existing.objectID)
            } else {
                // Create new world from URL with unique name
                let world = World.createWorld(from: url, in: context)
                world.isHidden = false
                
                // Generate unique name if needed
                let baseName = host
                var counter = 1
                var uniqueName = baseName
                let maxAttempts = 1000 // Safety limit to prevent infinite loop
                
                while counter < maxAttempts {
                    let nameCheck = NSPredicate(format: "name == %@ AND isHidden == NO", uniqueName)
                    let nameRequest: NSFetchRequest<World> = World.fetchRequest()
                    nameRequest.predicate = nameCheck
                    
                    let nameExists = (try? context.fetch(nameRequest).isEmpty) == false
                    if !nameExists {
                        break
                    }
                    
                    counter += 1
                    uniqueName = "\(baseName) \(counter)"
                }
                
                // If we hit the max attempts, use timestamp to ensure uniqueness
                if counter >= maxAttempts {
                    uniqueName = "\(baseName) \(Int(Date().timeIntervalSince1970))"
                }
                
                world.name = uniqueName
                
                try context.save()
                NotificationCenter.default.post(name: .worldChanged, object: world.objectID)
            }
            
            return true
        } catch {
            print("Error handling URL: \(error)")
            return false
        }
    }
    
    // MARK: - App State Handling
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Cancel all local notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Validate radial control positions
        RadialControl.validateRadialPositions()
        
        // Notify that app became active (for connection management)
        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Notify that app will resign active (for connection management)
        NotificationCenter.default.post(name: .appWillResignActive, object: nil)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Notify that app entered background (for connection management)
        NotificationCenter.default.post(name: .appDidEnterBackground, object: nil)
        
        // Cancel all local notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Save Core Data context
        PersistenceController.shared.save()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Notify that app will enter foreground (for connection management)
        NotificationCenter.default.post(name: .appWillEnterForeground, object: nil)
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Cancel all local notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Save Core Data context
        PersistenceController.shared.save()
    }
    
    // MARK: - Private Methods
    
    private func setupCoreData() {
        // Core Data setup is handled by PersistenceController
        _ = PersistenceController.shared
    }
    
    private func setupDefaultUserDefaults() {
        let defaults: [String: Any] = [
            UserDefaultsKeys.initialWorldsCreated: false,
            UserDefaultsKeys.localEcho: true,
            UserDefaultsKeys.autocorrect: false,
            UserDefaultsKeys.moveControl: RadialControlPosition.right.rawValue,
            UserDefaultsKeys.connectOnStartup: false,
            UserDefaultsKeys.stringEncoding: "ASCII",
            UserDefaultsKeys.keyboardStyle: true,
            UserDefaultsKeys.radialControl: RadialControlPosition.left.rawValue,
            UserDefaultsKeys.radialCommands: ["up", "in", "down", "out", "look"],
            UserDefaultsKeys.radialControlStyle: RadialControlStyle.minimal.rawValue,
            UserDefaultsKeys.radialControlOpacity: 1.0,
            UserDefaultsKeys.radialControlSize: 1.0,
            UserDefaultsKeys.radialControlLabelsVisible: false,
            UserDefaultsKeys.topBarAlwaysVisible: false,
            UserDefaultsKeys.autocapitalization: false,
            UserDefaultsKeys.semicolonCommands: true,
            UserDefaultsKeys.semicolonCommandDelimiter: ";",
            UserDefaultsKeys.autoLogging: true,
            UserDefaultsKeys.backgroundAudioEnabled: true
        ]
        
        UserDefaults.standard.register(defaults: defaults)
    }
    
    private func migratePasswordsIfNeeded() {
        // Check if migration has already been completed
        guard !UserDefaults.standard.bool(forKey: "KeychainMigrationCompleted") else {
            return
        }
        
        // Perform migration on background queue
        DispatchQueue.global(qos: .utility).async {
            KeychainManager.shared.migratePasswordsFromCoreData()
        }
    }
    
    private func setupAppStateNotifications() {
        // Register for app state change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: .appDidBecomeActive,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: .appWillResignActive,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: .appDidEnterBackground,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppStateChange),
            name: .appWillEnterForeground,
            object: nil
        )
    }
    
    @objc private func handleAppStateChange(_ notification: Notification) {
        // Forward app state changes to the main view controller
        if let container = window?.rootViewController as? ClientContainer {
            container.handleAppStateChange(notification.name)
        }
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let worldChanged = Notification.Name("kNotificationWorldChanged")
    static let urlTapped = Notification.Name("kNotificationURLTapped")
    static let appDidBecomeActive = Notification.Name("kNotificationAppDidBecomeActive")
    static let appWillResignActive = Notification.Name("kNotificationAppWillResignActive")
    static let appDidEnterBackground = Notification.Name("kNotificationAppDidEnterBackground")
    static let appWillEnterForeground = Notification.Name("kNotificationAppWillEnterForeground")
}

// MARK: - User Defaults Keys

struct UserDefaultsKeys {
    static let initialWorldsCreated = "kPrefInitialWorldsCreated"
    static let localEcho = "kPrefLocalEcho"
    static let autocorrect = "kPrefAutocorrect"
    static let moveControl = "kPrefMoveControl"
    static let connectOnStartup = "kPrefConnectOnStartup"
    static let stringEncoding = "kPrefStringEncoding"
    static let keyboardStyle = "kPrefKeyboardStyle"
    static let radialControl = "kPrefRadialControl"
    static let radialCommands = "kPrefRadialCommands"
    static let radialControlStyle = "kPrefRadialControlStyle"
    static let radialControlOpacity = "kPrefRadialControlOpacity"
    static let radialControlSize = "kPrefRadialControlSize"
    static let radialControlLabelsVisible = "kPrefRadialControlLabelsVisible"
    static let topBarAlwaysVisible = "kPrefTopBarAlwaysVisible"
    static let autocapitalization = "kPrefAutocapitalization"
    static let semicolonCommands = "kPrefSemicolonCommands"
    static let semicolonCommandDelimiter = "kPrefSemicolonCommandDelimiter"
    static let leftRadialPosition = "kPrefLeftRadialPosition"
    static let rightRadialPosition = "kPrefRightRadialPosition"
    static let autoLogging = "kPrefAutoLogging"
    
    // Phase 2 - New settings keys
    static let autoSendCommands = "kPrefAutoSendCommands"
    static let saveCommandHistory = "kPrefSaveCommandHistory"
    static let autoCapitalization = "kPrefAutoCapitalization"
    static let smartPunctuation = "kPrefSmartPunctuation"
    static let commandHistory = "kPrefCommandHistory"
    static let commandCompletion = "kPrefCommandCompletion"
    static let autoReconnect = "kPrefAutoReconnect"
    static let connectionTimeout = "kPrefConnectionTimeout"
    static let showNumberRow = "kPrefShowNumberRow"
    static let showPunctuationRow = "kPrefShowPunctuationRow"
    static let showTabKey = "kPrefShowTabKey"
    static let showArrowKeys = "kPrefShowArrowKeys"
    static let showFunctionKeys = "kPrefShowFunctionKeys"
    static let useBoldText = "kPrefUseBoldText"
    static let useDynamicType = "kPrefUseDynamicType"
    static let followSystemAppearance = "kPrefFollowSystemAppearance"
    static let useHighContrast = "kPrefUseHighContrast"
    static let reduceMotion = "kPrefReduceMotion"
    static let lineSpacing = "kPrefLineSpacing"
    static let enableANSIColors = "kPrefEnableANSIColors"
    static let enable256Colors = "kPrefEnable256Colors"
    static let enableTrueColor = "kPrefEnableTrueColor"
    static let backgroundAudioEnabled = "kPrefBackgroundAudioEnabled"
}

// MARK: - Radial Control Position

enum RadialControlPosition: Int, CaseIterable {
    case left = 0
    case right = 1
    case hidden = 2
} 
