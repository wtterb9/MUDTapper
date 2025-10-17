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
        URLHandler.shared.handleTelnetURL(url)
    }
} 