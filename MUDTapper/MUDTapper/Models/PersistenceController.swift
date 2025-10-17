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
            Logger.logCoreDataError("Preview context save error", error: error)
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
                Logger.fault("Core Data initialization failed", error: error, category: Logger.coreData)
                
                // Show user-facing error alert
                DispatchQueue.main.async {
                    self?.showCoreDataError(error)
                }
            } else {
                self?.isInitialized = true
                Logger.info("Core Data initialized successfully", category: Logger.coreData)
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    // MARK: - Error Handling
    
    private func showCoreDataError(_ error: Error) {
        ErrorPresenter.showError(
            title: "Database Error",
            message: "MUDTapper encountered a problem initializing its database. The app may not function correctly.",
            error: error
        )
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
                Logger.error("Core Data save failed", error: nsError, category: Logger.coreData)
                
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
        ErrorPresenter.showError(
            title: "Save Error",
            message: "Failed to save your changes. The app has reverted to the last saved state.",
            error: error
        )
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