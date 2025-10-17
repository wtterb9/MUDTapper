import Foundation
import CoreData

enum GagType: Int32, CaseIterable {
    case contains = 0
    case exact = 1
    case regex = 2
    
    var description: String {
        switch self {
        case .contains:
            return "Contains Text"
        case .exact:
            return "Exact Match"
        case .regex:
            return "Regular Expression"
        }
    }
    
    static var allDescriptions: [String] {
        return GagType.allCases.map { $0.description }
    }
}

@objc(Gag)
public class Gag: NSManagedObject {
    
    // MARK: - Core Data Properties
    
    @NSManaged public var isEnabled: Bool
    @NSManaged public var gag: String?
    @NSManaged public var gagType: Int32
    @NSManaged public var isHidden: Bool
    @NSManaged public var lastModified: Date?
    
    // MARK: - Relationships
    
    @NSManaged public var world: World?
    
    // MARK: - Computed Properties
    
    var gagTypeEnum: GagType {
        get {
            return GagType(rawValue: gagType) ?? .contains
        }
        set {
            gagType = newValue.rawValue
        }
    }
    
    var canSave: Bool {
        guard let gag = gag, !gag.isEmpty else { return false }
        return true
    }
    
    // MARK: - Creation
    
    static func createGag(in context: NSManagedObjectContext) -> Gag {
        let gag = Gag(context: context)
        gag.isEnabled = true
        gag.isHidden = false
        gag.gagType = GagType.contains.rawValue
        gag.lastModified = Date()
        return gag
    }
    
    // MARK: - Predicates
    
    static func predicateForGags(with world: World, active: Bool) -> NSPredicate {
        return NSPredicate(format: "isHidden == NO AND isEnabled == %@ AND world == %@", 
                          NSNumber(value: active), world)
    }
    
    // MARK: - Gag Matching
    
    func matches(line: String) -> Bool {
        guard let gagText = gag, !gagText.isEmpty else { return false }
        guard !line.isEmpty else { return false }
        
        switch gagTypeEnum {
        case .contains:
            return line.lowercased().contains(gagText.lowercased())
        case .exact:
            return line.lowercased() == gagText.lowercased()
        case .regex:
            do {
                let regex = try NSRegularExpression(pattern: gagText, options: [.caseInsensitive])
                let range = NSRange(location: 0, length: line.utf16.count)
                return regex.firstMatch(in: line, options: [], range: range) != nil
            } catch {
                Logger.warning("Invalid regex pattern in gag: \(gagText)", category: Logger.automation)
                return false
            }
        }
    }
}

// MARK: - Core Data Fetch Request

extension Gag {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Gag> {
        return NSFetchRequest<Gag>(entityName: "Gag")
    }
} 