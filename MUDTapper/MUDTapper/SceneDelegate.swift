import UIKit
import CoreData
import UserNotifications

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = ClientContainer()
        window?.makeKeyAndVisible()
        
        // Handle any URLs that were used to launch the app
        if let urlContext = connectionOptions.urlContexts.first {
            handleURL(urlContext.url)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Cancel all local notifications when app becomes active
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        // Validate radial control positions
        RadialControl.validateRadialPositions()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from active to inactive state.
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Save Core Data context when entering background
        PersistenceController.shared.save()
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleURL(url)
    }
    
    // MARK: - Private Methods
    
    private func handleURL(_ url: URL) {
        guard let host = url.host, url.scheme == "telnet" else { return }
        
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
        } catch {
            print("Error handling URL: \(error)")
        }
    }
} 