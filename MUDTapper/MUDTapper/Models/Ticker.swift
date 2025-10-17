import Foundation
import CoreData

/// Represents a timed command executor (ticker)
///
/// Tickers automatically execute commands at regular intervals.
/// Useful for repeated actions like healing, status checks, or auto-walking.
@objc(Ticker)
public class Ticker: NSManagedObject {
    
    // MARK: - Core Data Properties
    
    @NSManaged public var isEnabled: Bool
    @NSManaged public var interval: Double
    @NSManaged public var commands: String?
    @NSManaged public var soundFileName: String?
    @NSManaged public var isHidden: Bool
    @NSManaged public var lastModified: Date?
    
    // MARK: - Relationships
    
    @NSManaged public var world: World?
    
    // MARK: - Computed Properties
    
    var canSave: Bool {
        guard interval > 0 else { return false }
        guard let commands = commands, !commands.isEmpty else { return false }
        return true
    }
    
    // MARK: - Creation
    
    static func createTicker(in context: NSManagedObjectContext) -> Ticker {
        let ticker = Ticker(context: context)
        ticker.isEnabled = true
        ticker.isHidden = false
        ticker.interval = AppConstants.Automation.defaultTickerInterval
        ticker.lastModified = Date()
        return ticker
    }
    
    // MARK: - Predicates
    
    static func predicateForTickers(with world: World, active: Bool) -> NSPredicate {
        return NSPredicate(format: "isHidden == NO AND isEnabled == %@ AND world == %@", 
                          NSNumber(value: active), world)
    }
    
    // MARK: - Command Processing
    
    func tickerCommands() -> [String] {
        guard let commands = commands, !commands.isEmpty else { return [] }
        
        return commands.commandsFromUserInput()
    }
}

// MARK: - Core Data Fetch Request

extension Ticker {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Ticker> {
        return NSFetchRequest<Ticker>(entityName: "Ticker")
    }
} 