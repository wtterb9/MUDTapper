import Foundation
import CoreData
import UIKit

/// Represents a MushClient-style trigger for automated text matching and response
///
/// Triggers can match text using various methods (wildcard, regex, exact, substring, etc.)
/// and execute commands, play sounds, highlight text, or run Lua scripts when matched.
/// Supports advanced features like variable capture, conditional logic, and priority ordering.
@objc(Trigger)
public class Trigger: NSManagedObject {
    
    // MARK: - MushClient-Style Trigger Types
    
    enum TriggerType: Int32, CaseIterable {
        case wildcard = 0       // MushClient default - uses * and ?
        case regex = 1          // Regular expressions
        case exact = 2          // Exact match
        case substring = 3      // Contains substring
        case beginsWith = 4     // Starts with
        case endsWith = 5       // Ends with
        
        var displayName: String {
            switch self {
            case .wildcard: return "Wildcard (*?)"
            case .regex: return "Regular Expression"
            case .exact: return "Exact Match"
            case .substring: return "Substring"
            case .beginsWith: return "Begins With"
            case .endsWith: return "Ends With"
            }
        }
        
        var description: String {
            switch self {
            case .wildcard: return "Use * for any text, ? for any character (MushClient style)"
            case .regex: return "Full regular expression support with named groups"
            case .exact: return "Line must match exactly"
            case .substring: return "Line must contain this text"
            case .beginsWith: return "Line must start with this text"
            case .endsWith: return "Line must end with this text"
            }
        }
        
        var example: String {
            switch self {
            case .wildcard: return "* says '*'"
            case .regex: return "(?<name>\\w+) says '(?<message>.*)'"
            case .exact: return "You are hungry."
            case .substring: return "says"
            case .beginsWith: return "You"
            case .endsWith: return "hungry."
            }
        }
    }
    
    // MARK: - MushClient-Style Trigger Options
    
    enum TriggerOption: String, CaseIterable {
        case enabled = "enabled"
        case oneShot = "oneshot"
        case temporary = "temporary"
        case keepEvaluating = "keep_evaluating"
        case ignoreCase = "ignore_case"
        case expandVariables = "expand_variables"
        case omitFromOutput = "omit_from_output"
        case omitFromLog = "omit_from_log"
        case lowercaseWildcard = "lowercase_wildcard"
        
        var displayName: String {
            switch self {
            case .enabled: return "Enabled"
            case .oneShot: return "One Shot"
            case .temporary: return "Temporary"
            case .keepEvaluating: return "Keep Evaluating"
            case .ignoreCase: return "Ignore Case"
            case .expandVariables: return "Expand Variables"
            case .omitFromOutput: return "Omit from Output"
            case .omitFromLog: return "Omit from Log"
            case .lowercaseWildcard: return "Lowercase Wildcard"
            }
        }
        
        var description: String {
            switch self {
            case .enabled: return "Trigger is active"
            case .oneShot: return "Delete trigger after first match"
            case .temporary: return "Don't save trigger to world file"
            case .keepEvaluating: return "Continue checking other triggers after this one matches"
            case .ignoreCase: return "Case-insensitive matching"
            case .expandVariables: return "Expand variables in trigger pattern"
            case .omitFromOutput: return "Don't display the matching line"
            case .omitFromLog: return "Don't log the matching line"
            case .lowercaseWildcard: return "Convert wildcards to lowercase before matching"
            }
        }
    }
    
    // MARK: - Core Data Properties
    
    @NSManaged public var isEnabled: Bool
    @NSManaged public var trigger: String?
    @NSManaged public var commands: String?
    @NSManaged public var soundFileName: String?
    @NSManaged public var triggerType: Int32
    @NSManaged public var highlightColor: String?
    @NSManaged public var vibrate: Bool
    @NSManaged public var isHidden: Bool
    @NSManaged public var lastModified: Date?
    
    // MushClient-style properties
    @NSManaged public var priority: Int32           // Higher numbers = higher priority
    @NSManaged public var group: String?            // Trigger group name
    @NSManaged public var label: String?            // User-friendly name
    @NSManaged public var sequence: Int32           // For multi-line triggers
    @NSManaged public var options: String?          // JSON string of TriggerOption flags
    @NSManaged public var matchCount: Int32         // How many times this trigger has fired
    @NSManaged public var variables: String?        // JSON string of captured variables
    @NSManaged public var script: String?           // Optional script code
    
    // MARK: - Relationships
    
    @NSManaged public var world: World?
    
    // MARK: - Computed Properties
    
    var triggerTypeEnum: TriggerType {
        get { TriggerType(rawValue: triggerType) ?? .wildcard }
        set { triggerType = newValue.rawValue }
    }
    
    var triggerOptions: Set<TriggerOption> {
        get {
            guard let optionsString = options else { return [.enabled, .ignoreCase] }
            guard let data = optionsString.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return [.enabled, .ignoreCase]
            }
            return Set(array.compactMap { TriggerOption(rawValue: $0) })
        }
        set {
            let array = Array(newValue).map { $0.rawValue }
            options = try? String(data: JSONEncoder().encode(array), encoding: .utf8)
        }
    }
    
    var capturedVariables: [String: String] {
        get {
            guard let variablesString = variables else { return [:] }
            guard let data = variablesString.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            variables = try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)
        }
    }
    
    var isActive: Bool {
        return triggerOptions.contains(.enabled) && !isHidden
    }
    
    var isOneShot: Bool {
        return triggerOptions.contains(.oneShot)
    }
    
    var shouldKeepEvaluating: Bool {
        return triggerOptions.contains(.keepEvaluating)
    }
    
    var shouldIgnoreCase: Bool {
        return triggerOptions.contains(.ignoreCase)
    }
    
    var shouldOmitFromOutput: Bool {
        return triggerOptions.contains(.omitFromOutput)
    }
    
    var shouldOmitFromLog: Bool {
        return triggerOptions.contains(.omitFromLog)
    }
    
    var displayName: String {
        return label ?? trigger ?? "Unnamed Trigger"
    }
    
    // MARK: - MushClient-Style Pattern Matching
    
    // Improved regex cache using NSCache for automatic memory management
    private static let regexCache = NSCache<NSString, NSRegularExpression>()
    
    private var compiledRegex: NSRegularExpression? {
        guard let pattern = trigger else { return nil }
        
        // Create cache key from pattern, options, and type
        let options: NSRegularExpression.Options = shouldIgnoreCase ? [.caseInsensitive] : []
        let cacheKey = "\(pattern)|\(shouldIgnoreCase ? 1 : 0)|\(triggerTypeEnum.rawValue)" as NSString
        
        // Check cache first
        if let cached = Self.regexCache.object(forKey: cacheKey) {
            return cached
        }
        
        // Compile regex based on trigger type with validation
        let compiled: NSRegularExpression?
        switch triggerTypeEnum {
        case .regex:
            // Use safe compilation with validation
            compiled = RegexValidator.safeCompile(pattern: pattern, options: options)
        case .wildcard:
            // Convert MushClient wildcard to regex
            var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
            regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: "(.*?)")  // * any text
            regexPattern = regexPattern.replacingOccurrences(of: "\\?", with: "(.)")    // ? any single char
            let fullPattern = "^" + regexPattern + "$"
            // Use safe compilation with validation
            compiled = RegexValidator.safeCompile(pattern: fullPattern, options: options)
        default:
            compiled = nil
        }
        
        // Store in cache if compilation succeeded
        if let regex = compiled {
            Self.regexCache.setObject(regex, forKey: cacheKey)
        }
        
        return compiled
    }
    
    // MARK: - MushClient-Style Matching Logic
    
    /// Check if this trigger matches the given line of text
    /// - Parameter line: The line of text to test
    /// - Returns: true if the trigger matches, false otherwise
    func matches(line: String) -> Bool {
        guard isActive else { return false }
        guard let pattern = trigger, !pattern.isEmpty else { return false }
        
        let testLine = shouldIgnoreCase ? line.lowercased() : line
        let testPattern = shouldIgnoreCase ? pattern.lowercased() : pattern
        
        let result: Bool
        switch triggerTypeEnum {
        case .exact:
            result = testLine.trimmingCharacters(in: .whitespacesAndNewlines) == testPattern
            
        case .substring:
            result = testLine.contains(testPattern)
            
        case .beginsWith:
            result = testLine.hasPrefix(testPattern)
            
        case .endsWith:
            result = testLine.hasSuffix(testPattern)
            
        case .regex, .wildcard:
            guard let regex = compiledRegex else { return false }
            let range = NSRange(location: 0, length: line.utf16.count)
            result = regex.firstMatch(in: line, options: [], range: range) != nil
        }
        
        return result
    }
    
    // MARK: - MushClient-Style Variable Capture
    
    func captureVariables(from line: String) -> [String: String] {
        guard let pattern = trigger else { return [:] }
        
        var variables: [String: String] = [:]
        
        switch triggerTypeEnum {
        case .regex:
            variables = captureRegexVariables(from: line)
        case .wildcard:
            variables = captureWildcardVariables(from: line)
        default:
            break
        }
        
        // Option: for wildcard triggers, lowercase captured groups if requested
        if triggerTypeEnum == .wildcard && triggerOptions.contains(.lowercaseWildcard) {
            var lowered: [String: String] = [:]
            for (key, value) in variables {
                // Only lowercase numeric and %n captures, not reserved keys like "line"/"trigger"
                if Int(key) != nil || key.hasPrefix("%") {
                    lowered[key] = value.lowercased()
                } else {
                    lowered[key] = value
                }
            }
            variables = lowered
        }
        
        // Always provide these standard variables
        variables["line"] = line
        variables["trigger"] = pattern
        variables["match_count"] = "\(matchCount + 1)"
        
        return variables
    }
    
    private func captureRegexVariables(from line: String) -> [String: String] {
        guard let regex = compiledRegex else { return [:] }
        
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return [:]
        }
        
        var variables: [String: String] = [:]
        
        // Numbered captures ($0, $1, $2, etc.) - $0 is the full match
        for i in 0..<match.numberOfRanges {
            let captureRange = match.range(at: i)
            if captureRange.location != NSNotFound,
               let range = Range(captureRange, in: line) {
                let capturedValue = String(line[range])
                variables["\(i)"] = capturedValue  // For $0, $1, $2, etc.
                if i > 0 {
                    variables["%\(i)"] = capturedValue // For %1, %2, etc. (MushClient style) - skip %0
                }
            }
        }
        
        // Named captures (if using named groups in regex)
        // Extract named groups if present in the pattern
        if let pattern = trigger {
            extractNamedGroups(from: pattern, match: match, line: line, variables: &variables)
        }
        
        return variables
    }
    
    private func extractNamedGroups(from pattern: String, match: NSTextCheckingResult, line: String, variables: inout [String: String]) {
        // Look for named groups in the pattern: (?<name>...) or (?P<name>...)
        let namedGroupPattern = #"\(\?P?<(\w+)>.*?\)"#
        
        do {
            let regex = try NSRegularExpression(pattern: namedGroupPattern, options: [])
            let patternRange = NSRange(location: 0, length: pattern.utf16.count)
            let matches = regex.matches(in: pattern, options: [], range: patternRange)
            
            for (index, namedMatch) in matches.enumerated() {
                if namedMatch.numberOfRanges > 1 {
                    let nameRange = namedMatch.range(at: 1)
                    if let nameSwiftRange = Range(nameRange, in: pattern) {
                        let groupName = String(pattern[nameSwiftRange])
                        
                        // Map to the corresponding capture group (index + 1 since $0 is full match)
                        let captureIndex = index + 1
                        if captureIndex < match.numberOfRanges {
                            let captureRange = match.range(at: captureIndex)
                            if captureRange.location != NSNotFound,
                               let range = Range(captureRange, in: line) {
                                variables[groupName] = String(line[range])
                            }
                        }
                    }
                }
            }
        } catch {
            // Ignore named group extraction errors
        }
    }
    
    private func captureWildcardVariables(from line: String) -> [String: String] {
        guard let regex = compiledRegex else { return [:] }
        
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return [:]
        }
        
        var variables: [String: String] = [:]
        
        // For wildcards, we capture in order: 1, 2, etc. (the key is just the number)
        // Also provide both %n and $n formats for compatibility
        for i in 1..<match.numberOfRanges {
            let captureRange = match.range(at: i)
            if captureRange.location != NSNotFound,
               let range = Range(captureRange, in: line) {
                let capturedValue = String(line[range])
                variables["\(i)"] = capturedValue  // For $1, $2, etc.
                variables["%\(i)"] = capturedValue // For %1, %2, etc. (MushClient style)
            }
        }
        
        return variables
    }
    
    // MARK: - MushClient-Style Command Processing
    
    func processedCommands(for line: String) -> [String] {
        guard let commandString = commands, !commandString.isEmpty else { return [] }
        
        // Capture variables from the matched line
        let variables = captureVariables(from: line)
        
        // Split commands by semicolon (MushClient style)
        let delimiter = ";"
        let baseCommands = commandString.components(separatedBy: delimiter)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Process each command with variable substitution and conditional logic
        var processedCommands: [String] = []
        
        for command in baseCommands {
            let processed = processCommand(command, variables: variables)
            processedCommands.append(contentsOf: processed)
        }
        
        return processedCommands
    }
    
    // MARK: - MushClient-Style Conditional Logic
    
    private func processCommand(_ command: String, variables: [String: String]) -> [String] {
        var processedCommand = command
        
        // First, substitute variables
        for (key, value) in variables {
            processedCommand = processedCommand.replacingOccurrences(of: "%\(key)", with: value)
            processedCommand = processedCommand.replacingOccurrences(of: "$\(key)", with: value)
        }
        
        // Check for conditional statements (supports both @if and if)
        if processedCommand.hasPrefix("@if ") || processedCommand.hasPrefix("if ") {
            return processConditionalCommand(processedCommand, variables: variables)
        }
        
        return [processedCommand]
    }
    
    private func processConditionalCommand(_ command: String, variables: [String: String]) -> [String] {
        
        // Parse both @if and if (condition) {true_command} {false_command}
        let pattern = #"@?if\s*\(([^)]+)\)\s*\{([^}]*)\}(?:\s*\{([^}]*)\})?"#
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: command.utf16.count)
            
            if let match = regex.firstMatch(in: command, options: [], range: range) {
                // Extract condition, true command, false command
                let conditionRange = match.range(at: 1)
                let trueCommandRange = match.range(at: 2)
                let falseCommandRange = match.range(at: 3)
                
                guard conditionRange.location != NSNotFound,
                      trueCommandRange.location != NSNotFound,
                      let conditionSwiftRange = Range(conditionRange, in: command),
                      let trueCommandSwiftRange = Range(trueCommandRange, in: command) else {
                    return [command] // Return original if parsing fails
                }
                
                let condition = String(command[conditionSwiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let trueCommand = String(command[trueCommandSwiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                var falseCommand = ""
                if falseCommandRange.location != NSNotFound,
                   let falseCommandSwiftRange = Range(falseCommandRange, in: command) {
                    falseCommand = String(command[falseCommandSwiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Evaluate condition
                let conditionResult = evaluateCondition(condition, variables: variables)
                
                if conditionResult {
                    if !trueCommand.isEmpty {
                        return trueCommand.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }
                } else {
                    if !falseCommand.isEmpty {
                        return falseCommand.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    }
                }
                
                return [] // No commands to execute
            }
        } catch {
            // Ignore regex errors
        }
        
        return [command] // Return original if not a valid @if statement
    }
    
    private func evaluateCondition(_ condition: String, variables: [String: String]) -> Bool {
        // Substitute variables in condition
        var evaluatedCondition = condition
        for (key, value) in variables {
            evaluatedCondition = evaluatedCondition.replacingOccurrences(of: "%\(key)", with: value)
            evaluatedCondition = evaluatedCondition.replacingOccurrences(of: "$\(key)", with: value)
        }
        
        // Support various condition types
        let trimmed = evaluatedCondition.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Equality checks: var == "value"
        if trimmed.range(of: #"\s*([^=!<>]+)\s*==\s*"([^"]*)"|\s*([^=!<>]+)\s*==\s*([^=!<>\s]+)"#, options: .regularExpression) != nil {
            let parts = trimmed.components(separatedBy: "==").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 {
                let left = parts[0]
                let right = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let result = left == right
                return result
            }
        }
        
        // Inequality checks: var != "value"
        if trimmed.range(of: #"\s*([^=!<>]+)\s*!=\s*"([^"]*)"|\s*([^=!<>]+)\s*!=\s*([^=!<>\s]+)"#, options: .regularExpression) != nil {
            let parts = trimmed.components(separatedBy: "!=").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 {
                let left = parts[0]
                let right = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let result = left != right
                return result
            }
        }
        
        // Contains checks: var contains "substring"
        if trimmed.contains(" contains ") {
            let parts = trimmed.components(separatedBy: " contains ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 {
                let left = parts[0]
                let right = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let result = left.localizedCaseInsensitiveContains(right)
                return result
            }
        }
        
        // Numeric comparisons: var > 100, var < 50
        if trimmed.range(of: #"\s*([^<>=!]+)\s*([<>=]+)\s*(\d+)"#, options: .regularExpression) != nil {
            do {
                let regex = try NSRegularExpression(pattern: #"\s*([^<>=!]+)\s*([<>=]+)\s*(\d+)"#)
                let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = regex.firstMatch(in: trimmed, range: nsRange) {
                let leftRange = Range(match.range(at: 1), in: trimmed)!
                let operatorRange = Range(match.range(at: 2), in: trimmed)!
                let rightRange = Range(match.range(at: 3), in: trimmed)!
                
                let left = String(trimmed[leftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let operator_ = String(trimmed[operatorRange])
                let right = String(trimmed[rightRange])
                
                if let leftValue = Double(left), let rightValue = Double(right) {
                    var result = false
                    switch operator_ {
                    case ">":
                        result = leftValue > rightValue
                    case "<":
                        result = leftValue < rightValue
                    case ">=":
                        result = leftValue >= rightValue
                    case "<=":
                        result = leftValue <= rightValue
                    default:
                        result = false
                    }
                    
                    return result
                }
                }
            } catch {
                // Invalid pattern; treat as false
            }
        }
        
        // Boolean checks: just a variable name or "true"/"false"
        if trimmed.lowercased() == "true" || trimmed == "1" {
            return true
        }
        if trimmed.lowercased() == "false" || trimmed == "0" || trimmed.isEmpty {
            return false
        }
        
        // Check if it's just a variable that exists and is non-empty
        if let value = variables[trimmed] {
            return !value.isEmpty
        }
        
        return false
    }
    
    // MARK: - MushClient-Style Trigger Execution
    
    /// Execute this trigger for a matched line
    /// - Parameter line: The line of text that matched
    /// - Returns: true if other triggers should continue evaluating (keepEvaluating), false to stop
    func execute(for line: String) -> Bool {
        guard matches(line: line) else { return false }
        
        Logger.logTrigger("Executing trigger: '\(trigger ?? "")'")
        
        // Increment match count
        matchCount += 1
        lastModified = Date()
        
        // Capture and store variables
        capturedVariables = captureVariables(from: line)
        NotificationCenter.default.post(name: .triggerVariablesUpdated, object: self)
        
        // Execute commands
        var commands = processedCommands(for: line)
        // If a script is present, evaluate it as well (supports minimal Lua send("...") syntax)
        if let scriptCode = script?.trimmingCharacters(in: .whitespacesAndNewlines), !scriptCode.isEmpty {
            let lua = LuaScriptRuntime()
            let scriptCommands = lua.evaluate(script: scriptCode, variables: capturedVariables)
            if !scriptCommands.isEmpty { commands.append(contentsOf: scriptCommands) }
        }
        Logger.logTrigger("Processed commands: \(commands)")
        
        // Send notification with trigger details
        let userInfo: [String: Any] = [
            "trigger": self,
            "line": line,
            "commands": commands,
            "variables": capturedVariables,
            "shouldOmitFromOutput": shouldOmitFromOutput
        ]
        
        Logger.logTrigger("Posting trigger notification with \(commands.count) command(s)")
        NotificationCenter.default.post(name: .triggerDidFire, object: world, userInfo: userInfo)
        
        // Handle one-shot triggers
        if isOneShot {
            isHidden = true
            try? managedObjectContext?.save()
        }
        
        // Return whether to continue evaluating other triggers
        return shouldKeepEvaluating
    }
    
    // MARK: - MushClient-Style Trigger Management
    
    static func createMushClientTrigger(
        pattern: String,
        commands: String,
        type: TriggerType = .wildcard,
        options: Set<TriggerOption> = [.enabled, .ignoreCase],
        priority: Int32 = 50,
        group: String? = nil,
        label: String? = nil,
        world: World,
        context: NSManagedObjectContext
    ) -> Trigger {
        let trigger = Trigger(context: context)
        trigger.trigger = pattern
        trigger.commands = commands
        trigger.triggerTypeEnum = type
        trigger.triggerOptions = options
        trigger.priority = priority
        trigger.group = group
        trigger.label = label
        trigger.world = world
        trigger.isHidden = false
        trigger.lastModified = Date()
        trigger.matchCount = 0
        return trigger
    }
    
    // MARK: - Predicates for MushClient-style queries
    
    static func predicateForActiveTriggersInGroup(_ group: String?, world: World) -> NSPredicate {
        if let group = group {
            return NSPredicate(format: "isHidden == NO AND world == %@ AND group == %@", world, group)
        } else {
            return NSPredicate(format: "isHidden == NO AND world == %@ AND group == nil", world)
        }
    }
    
    static func predicateForTriggersByPriority(world: World) -> NSPredicate {
        return NSPredicate(format: "isHidden == NO AND world == %@", world)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let triggerVariablesUpdated = Notification.Name("triggerVariablesUpdated")
}

// MARK: - Minimal Lua-like Scripting Runtime

/// A tiny interpreter that supports a subset of Lua-like commands for triggers.
/// Currently recognizes: send("text") and multiple lines; performs variable substitution for %n/$n and named keys.
/// This is intentionally small and embeddable; replace with a full Lua engine later if needed.
final class LuaScriptRuntime {
    func evaluate(script: String, variables: [String: String]) -> [String] {
        var results: [String] = []
        let rawLines = script.split(separator: "\n").map { String($0) }
        var env: [String: String] = variables
        
        var i = 0
        var inIf = false
        var executing = true
        var branchTaken = false
        
        while i < rawLines.count {
            let line = rawLines[i]
            i += 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("--") { continue }
            
            if let cond = parseIf(line: trimmed) {
                inIf = true
                executing = evaluateCondition(cond, env: env)
                branchTaken = executing
                continue
            }
            if let cond = parseElseIf(line: trimmed), inIf {
                if branchTaken {
                    executing = false
                } else {
                    executing = evaluateCondition(cond, env: env)
                    branchTaken = executing
                }
                continue
            }
            if isElse(line: trimmed), inIf {
                executing = !branchTaken
                continue
            }
            if isEnd(line: trimmed), inIf {
                inIf = false
                executing = true
                branchTaken = false
                continue
            }
            
            if let assign = parseAssignment(line: trimmed) {
                if executing {
                    let value = evaluateExpression(assign.value, env: env)
                    env[assign.name] = value
                }
                continue
            }
            
            if let payload = parseSendCall(from: trimmed) {
                if executing {
                    results.append(substitute(payload, with: env))
                }
                continue
            }
        }
        return results
    }
    
    private func parseSendCall(from line: String) -> String? {
        // Matches: send("...") or send('...')
        let pattern = #"^send\((?:\"([\s\S]*?)\"|'([\s\S]*?)')\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        for groupIndex in 1..<match.numberOfRanges {
            let r = match.range(at: groupIndex)
            if r.location != NSNotFound, let swiftRange = Range(r, in: line) {
                return String(line[swiftRange])
            }
        }
        return nil
    }
    
    // MARK: - Simple statements and expressions
    
    private func parseAssignment(line: String) -> (name: String, value: String)? {
        let pattern = #"^(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        let nameRange = match.range(at: 1)
        let valueRange = match.range(at: 2)
        if let n = Range(nameRange, in: line), let v = Range(valueRange, in: line) {
            return (String(line[n]), String(line[v]))
        }
        return nil
    }
    
    private func parseIf(line: String) -> String? {
        captureFirstGroup(line: line, pattern: #"^if\s+(.+?)\s+then$"#)
    }
    
    private func parseElseIf(line: String) -> String? {
        captureFirstGroup(line: line, pattern: #"^elseif\s+(.+?)\s+then$"#)
    }
    
    private func isElse(line: String) -> Bool { line == "else" }
    private func isEnd(line: String) -> Bool { line == "end" }
    
    private func captureFirstGroup(line: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        let r = match.range(at: 1)
        if r.location != NSNotFound, let swiftRange = Range(r, in: line) {
            return String(line[swiftRange])
        }
        return nil
    }
    
    private func evaluateExpression(_ expr: String, env: [String: String]) -> String {
        let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = parseQuotedString(trimmed) { return s }
        if Double(trimmed) != nil { return trimmed }
        return resolveIdentifier(trimmed, env: env)
    }
    
    private func parseQuotedString(_ s: String) -> String? {
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            let start = s.index(after: s.startIndex)
            let end = s.index(before: s.endIndex)
            return String(s[start..<end])
        }
        if s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2 {
            let start = s.index(after: s.startIndex)
            let end = s.index(before: s.endIndex)
            return String(s[start..<end])
        }
        return nil
    }
    
    private func evaluateCondition(_ condition: String, env: [String: String]) -> Bool {
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        if let (lhs, op, rhs) = parseBinary(cond: trimmed, operators: ["==", "~=", "!="]) {
            let left = resolveIdentifier(lhs, env: env)
            let right = evaluateExpression(rhs, env: env)
            switch op { case "==": return left == right; case "!=", "~=": return left != right; default: break }
        }
        if let (lhs, rhs) = parseContains(cond: trimmed) {
            let left = resolveIdentifier(lhs, env: env)
            let right = evaluateExpression(rhs, env: env)
            return left.localizedCaseInsensitiveContains(right)
        }
        if let (lhs, op, rhs) = parseBinary(cond: trimmed, operators: [">=", "<=", ">", "<"]) {
            let left = Double(resolveIdentifier(lhs, env: env)) ?? Double.nan
            let right = Double(evaluateExpression(rhs, env: env)) ?? Double.nan
            switch op { case ">": return left > right; case "<": return left < right; case ">=": return left >= right; case "<=": return left <= right; default: break }
        }
        if trimmed.lowercased() == "true" || trimmed == "1" { return true }
        if trimmed.lowercased() == "false" || trimmed == "0" { return false }
        return !resolveIdentifier(trimmed, env: env).isEmpty
    }
    
    private func parseBinary(cond: String, operators: [String]) -> (String, String, String)? {
        for op in operators {
            let parts = cond.components(separatedBy: op)
            if parts.count == 2 {
                return (parts[0].trimmingCharacters(in: .whitespaces), op, parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
    
    private func parseContains(cond: String) -> (String, String)? {
        let token = " contains "
        if let range = cond.range(of: token) {
            let lhs = String(cond[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rhs = String(cond[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (lhs, rhs)
        }
        return nil
    }
    
    private func resolveIdentifier(_ name: String, env: [String: String]) -> String {
        if let val = env[name] { return val }
        if Int(name) != nil, let val = env[name] { return val }
        return ""
    }
    
    private func substitute(_ text: String, with variables: [String: String]) -> String {
        var output = text
        // Replace named variables first to avoid clobbering digits
        for (key, value) in variables.sorted(by: { $0.key.count > $1.key.count }) {
            output = output.replacingOccurrences(of: "%\(key)", with: value)
            output = output.replacingOccurrences(of: "$\(key)", with: value)
        }
        return output
    }
}

// MARK: - Core Data Fetch Request

extension Trigger {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Trigger> {
        return NSFetchRequest<Trigger>(entityName: "Trigger")
    }
    
    static func fetchActiveTriggersOrderedByPriority(for world: World, context: NSManagedObjectContext) -> [Trigger] {
        let request: NSFetchRequest<Trigger> = Trigger.fetchRequest()
        request.predicate = NSPredicate(format: "isHidden == NO AND world == %@", world)
        request.sortDescriptors = [
            NSSortDescriptor(key: "priority", ascending: false),  // Higher priority first
            NSSortDescriptor(key: "sequence", ascending: true),   // Then by sequence
            NSSortDescriptor(key: "lastModified", ascending: true) // Then by creation order
        ]
        
        do {
            return try context.fetch(request)
        } catch {
            Logger.logCoreDataError("Error fetching triggers", error: error)
            return []
        }
    }
}

// MARK: - String Extensions

extension String {
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        return self.lowercased().hasPrefix(prefix.lowercased())
    }
    
    func localizedCaseInsensitiveHasSuffix(_ suffix: String) -> Bool {
        return self.lowercased().hasSuffix(suffix.lowercased())
    }
    
    func localizedCaseInsensitiveContains(_ substring: String) -> Bool {
        return self.lowercased().contains(substring.lowercased())
    }
} 