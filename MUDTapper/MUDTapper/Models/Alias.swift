import Foundation
import CoreData

/// Represents a command alias with parameter substitution support
///
/// Aliases allow short commands to expand into longer command sequences.
/// Supports parameter substitution using $1$, $2$, $*$ notation.
@objc(Alias)
public class Alias: NSManagedObject {
    
    // MARK: - Core Data Properties
    
    @NSManaged public var isEnabled: Bool
    @NSManaged public var name: String?
    @NSManaged public var commands: String?
    @NSManaged public var isHidden: Bool
    @NSManaged public var lastModified: Date?
    
    // MARK: - Relationships
    
    @NSManaged public var world: World?
    
    // MARK: - Computed Properties
    
    var canSave: Bool {
        guard let name = name, !name.isEmpty else { return false }
        guard let commands = commands, !commands.isEmpty else { return false }
        return true
    }
    
    // MARK: - Creation
    
    static func createAlias(in context: NSManagedObjectContext) -> Alias {
        let alias = Alias(context: context)
        alias.isEnabled = true
        alias.isHidden = false
        alias.lastModified = Date()
        return alias
    }
    
    // MARK: - Predicates
    
    static func predicateForAliases(with world: World, active: Bool) -> NSPredicate {
        return NSPredicate(format: "isHidden == NO AND isEnabled == %@ AND world == %@", 
                          NSNumber(value: active), world)
    }
    
    // MARK: - Alias Command Processing
    
    /// Process input through this alias, substituting parameters as needed
    /// - Parameter input: The full user input that triggered this alias
    /// - Returns: Array of commands to execute with parameter substitution applied
    func aliasCommands(for input: String) -> [String] {
        guard let commands = commands else { return [] }
        
        let commandList = commands.commandsFromUserInput()
        let inputWords = input.components(separatedBy: .whitespaces)
        
        // Remove the alias name from input words
        let filteredWords = inputWords.filter { word in
            guard let aliasName = name else { return true }
            return word.lowercased() != aliasName.lowercased()
        }
        
        let targetInput = filteredWords.joined(separator: " ")
        
        // Process command substitution patterns like $1$, $2$, $*$
        let commandIndexPattern = "\\$..?\\$"
        
        var processedCommands: [String] = []
        
        for command in commandList {
            var maxCommandIndex = 0
            var outString = command
            var didApplyMatching = false
            
            // Find all substitution markers
            let regex = try? NSRegularExpression(pattern: commandIndexPattern, 
                                               options: [.caseInsensitive, .useUnixLineSeparators])
            
            let matches = regex?.matches(in: command, options: [], 
                                       range: NSRange(location: 0, length: command.count)) ?? []
            
            for match in matches {
                let marker = String(command[Range(match.range, in: command)!])
                let indexString = marker.replacingOccurrences(of: "$", with: "")
                
                var replaceWith = ""
                
                if indexString == "*" {
                    // Replace with remainder of input from highest index onwards
                    if filteredWords.count > maxCommandIndex {
                        let remainingWords = Array(filteredWords[maxCommandIndex...])
                        replaceWith = remainingWords.joined(separator: " ")
                    }
                } else if let intVal = Int(indexString), intVal > 0 {
                    // $1$ -> index 0, $2$ -> index 1, etc.
                    let arrayIndex = intVal - 1
                    
                    if filteredWords.count > arrayIndex {
                        replaceWith = filteredWords[arrayIndex]
                        if arrayIndex >= maxCommandIndex {
                            maxCommandIndex = arrayIndex + 1
                        }
                    }
                }
                
                outString = outString.replacingOccurrences(of: marker, with: replaceWith)
                didApplyMatching = true
            }
            
            // If no substitution was applied, append the target input
            if !didApplyMatching && !targetInput.isEmpty {
                outString += " \(targetInput)"
            }
            
            // Check if this is a multi-session command (#all or #sessionname)
            if outString.hasPrefix("#") {
                // For multi-session commands, we need to ensure the command is properly formatted
                // and the target session exists
                if let spaceIndex = outString.firstIndex(of: " ") {
                    let _ = String(outString[outString.index(after: outString.startIndex)..<spaceIndex])
                    let command = String(outString[outString.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if !command.isEmpty {
                        processedCommands.append(outString)
                    }
                }
            } else {
                processedCommands.append(outString)
            }
        }
        
        return processedCommands.isEmpty ? [] : processedCommands
    }
}

// MARK: - Core Data Fetch Request

extension Alias {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Alias> {
        return NSFetchRequest<Alias>(entityName: "Alias")
    }
}

// MARK: - String Extension for Command Processing

extension String {
    func commandsFromUserInput() -> [String] {
        // Split commands by semicolon or newline
        let delimiter = UserDefaults.standard.string(forKey: UserDefaultsKeys.semicolonCommandDelimiter) ?? ";"
        
        return self.components(separatedBy: CharacterSet(charactersIn: delimiter + "\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
} 