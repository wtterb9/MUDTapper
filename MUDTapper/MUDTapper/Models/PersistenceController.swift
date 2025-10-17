import CoreData
import Foundation
import UIKit

class PersistenceController {
    static let shared = PersistenceController()
    
    // Track initialization state
    private(set) var initializationError: Error?
    private(set) var isInitialized: Bool = false
    
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample data for previews
        let sampleWorld = World(context: viewContext)
        sampleWorld.name = "Sample MUD"
        sampleWorld.hostname = "example.mud.com"
        sampleWorld.port = 4000
        sampleWorld.isDefault = false
        sampleWorld.isHidden = false
        sampleWorld.isSecure = false
        
        do {
            try viewContext.save()
        } catch {
            // In preview mode, log the error but don't crash
            print("Preview context save error: \(error)")
        }
        return result
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MUDTapper")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Enable automatic migration
        container.persistentStoreDescriptions.forEach { storeDescription in
            storeDescription.shouldMigrateStoreAutomatically = true
            storeDescription.shouldInferMappingModelAutomatically = true
        }
        
        container.loadPersistentStores { [weak self] _, error in
            if let error = error as NSError? {
                // Store the error for later handling instead of crashing
                self?.initializationError = error
                self?.isInitialized = false
                
                // Log the error
                print("Core Data initialization error: \(error), \(error.userInfo)")
                
                // Show user-facing error alert
                DispatchQueue.main.async {
                    self?.showCoreDataError(error)
                }
            } else {
                self?.isInitialized = true
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    // MARK: - Error Handling
    
    private func showCoreDataError(_ error: Error) {
        let alert = UIAlertController(
            title: "Database Error",
            message: "MUDTapper encountered a problem initializing its database. The app may not function correctly.\n\nError: \(error.localizedDescription)",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Try to find the top-most view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    var viewContext: NSManagedObjectContext {
        return container.viewContext
    }
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Core Data save error: \(nsError), \(nsError.userInfo)")
                
                // Try to recover by rolling back changes
                context.rollback()
                
                // Show user-facing error
                DispatchQueue.main.async {
                    self.showSaveError(nsError)
                }
            }
        }
    }
    
    private func showSaveError(_ error: NSError) {
        let alert = UIAlertController(
            title: "Save Error",
            message: "Failed to save your changes. The app has reverted to the last saved state.\n\nError: \(error.localizedDescription)",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Try to find the top-most view controller to present from
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            var presenter = rootViewController
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(alert, animated: true)
        }
    }
    
    func saveContext() {
        save()
    }
    
    // MARK: - Background Context Operations
    
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }
    
    func newBackgroundContext() -> NSManagedObjectContext {
        return container.newBackgroundContext()
    }
} 