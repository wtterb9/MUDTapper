import Foundation
import CoreData

/// Centralized URL handling for telnet:// URLs
class URLHandler {
    
    // MARK: - Singleton
    
    static let shared = URLHandler()
    private init() {}
    
    // MARK: - URL Handling
    
    /// Handle a telnet:// URL and create or select the appropriate world
    /// - Parameter url: The telnet URL to handle
    /// - Returns: true if the URL was handled successfully, false otherwise
    @discardableResult
    func handleTelnetURL(_ url: URL) -> Bool {
        guard let host = url.host, url.scheme == "telnet" else {
            return false
        }
        
        let context = PersistenceController.shared.viewContext
        let port = url.port ?? Int(AppConstants.Network.defaultTelnetPort)
        
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
                return true
            } else {
                // Create new world from URL with unique name
                let world = World.createWorld(from: url, in: context)
                world.isHidden = false
                
                // Generate unique name
                world.name = generateUniqueName(baseName: host, context: context)
                
                try context.save()
                NotificationCenter.default.post(name: .worldChanged, object: world.objectID)
                return true
            }
        } catch {
            Logger.logCoreDataError("Error handling URL", error: error)
            return false
        }
    }
    
    // MARK: - Private Helpers
    
    /// Generate a unique world name by appending a counter if needed
    /// - Parameters:
    ///   - baseName: The base name to use
    ///   - context: The Core Data context to check for existing names
    /// - Returns: A unique world name
    private func generateUniqueName(baseName: String, context: NSManagedObjectContext) -> String {
        var counter = 1
        var uniqueName = baseName
        let maxAttempts = AppConstants.Automation.maxUniqueNameAttempts
        
        while counter < maxAttempts {
            let nameCheck = NSPredicate(format: "name == %@ AND isHidden == NO", uniqueName)
            let nameRequest: NSFetchRequest<World> = World.fetchRequest()
            nameRequest.predicate = nameCheck
            
            let nameExists = (try? context.fetch(nameRequest).isEmpty) == false
            if !nameExists {
                return uniqueName
            }
            
            counter += 1
            uniqueName = "\(baseName) \(counter)"
        }
        
        // If we hit the max attempts, use timestamp to ensure uniqueness
        return "\(baseName) \(Int(Date().timeIntervalSince1970))"
    }
}

