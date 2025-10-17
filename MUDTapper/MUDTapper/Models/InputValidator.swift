import Foundation

/// Input validation and sanitization utilities
class InputValidator {
    
    // MARK: - Command Validation
    
    /// Sanitize user input to prevent command injection
    /// - Parameter input: Raw user input
    /// - Returns: Sanitized input safe for command execution
    static func sanitizeCommand(_ input: String) -> String {
        var sanitized = input
        
        // Trim whitespace
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove null bytes
        sanitized = sanitized.replacingOccurrences(of: "\0", with: "")
        
        // Remove any control characters except newline and tab
        sanitized = sanitized.filter { char in
            let scalar = char.unicodeScalars.first
            guard let value = scalar?.value else { return false }
            // Allow printable characters, newline, tab
            return (value >= 32 && value < 127) || value == 9 || value == 10 || value > 127
        }
        
        return sanitized
    }
    
    /// Validate that a command doesn't contain suspicious patterns
    /// - Parameter command: The command to validate
    /// - Returns: Warning message if suspicious, nil if safe
    static func validateCommandSafety(_ command: String) -> String? {
        // Check for extremely long commands (potential DoS)
        if command.count > 10000 {
            return "Command is too long (maximum 10,000 characters)"
        }
        
        // Check for excessive repetition (potential DoS)
        if hasExcessiveRepetition(command) {
            return "Command contains excessive repetition"
        }
        
        return nil
    }
    
    // MARK: - Text Validation
    
    /// Validate world name
    /// - Parameter name: The world name to validate
    /// - Returns: Error message if invalid, nil if valid
    static func validateWorldName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return "World name cannot be empty"
        }
        
        if trimmed.count > 100 {
            return "World name is too long (maximum 100 characters)"
        }
        
        // Check for invalid characters
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        if trimmed.rangeOfCharacter(from: invalidChars) != nil {
            return "World name contains invalid characters (/ \\ : * ? \" < > |)"
        }
        
        return nil
    }
    
    /// Validate hostname
    /// - Parameter hostname: The hostname to validate
    /// - Returns: Error message if invalid, nil if valid
    static func validateHostname(_ hostname: String) -> String? {
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return "Hostname cannot be empty"
        }
        
        if trimmed.count > 255 {
            return "Hostname is too long (maximum 255 characters)"
        }
        
        // Basic hostname format validation
        let hostnameRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?([.][a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$"
        let ipRegex = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        
        let hostnamePredicate = NSPredicate(format: "SELF MATCHES %@", hostnameRegex)
        let ipPredicate = NSPredicate(format: "SELF MATCHES %@", ipRegex)
        
        if !hostnamePredicate.evaluate(with: trimmed) && !ipPredicate.evaluate(with: trimmed) {
            return "Invalid hostname format. Must be a valid domain name or IP address."
        }
        
        return nil
    }
    
    /// Validate port number with comprehensive checks
    /// - Parameter port: The port number to validate
    /// - Returns: Error message if invalid, warning message for privileged ports, nil if valid
    static func validatePort(_ port: Int) -> String? {
        return World.validatePort(port)
    }
    
    // MARK: - Pattern Validation
    
    /// Validate trigger pattern
    /// - Parameters:
    ///   - pattern: The trigger pattern
    ///   - type: The trigger type
    /// - Returns: Error message if invalid, nil if valid
    static func validateTriggerPattern(_ pattern: String, type: Trigger.TriggerType) -> String? {
        if pattern.isEmpty {
            return "Pattern cannot be empty"
        }
        
        if pattern.count > 1000 {
            return "Pattern is too long (maximum 1,000 characters)"
        }
        
        // Validate regex patterns specifically
        if type == .regex {
            return RegexValidator.validatePattern(pattern)
        }
        
        return nil
    }
    
    /// Validate alias name
    /// - Parameter name: The alias name
    /// - Returns: Error message if invalid, nil if valid
    static func validateAliasName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return "Alias name cannot be empty"
        }
        
        if trimmed.count > 50 {
            return "Alias name is too long (maximum 50 characters)"
        }
        
        // Alias names should not contain spaces (they're used as command prefixes)
        if trimmed.contains(" ") {
            return "Alias name cannot contain spaces"
        }
        
        // Check for special characters that might cause issues
        let invalidChars = CharacterSet(charactersIn: ";#@")
        if trimmed.rangeOfCharacter(from: invalidChars) != nil {
            return "Alias name cannot contain special characters (; # @)"
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    private static func hasExcessiveRepetition(_ text: String) -> Bool {
        guard text.count > 100 else { return false }
        
        // Check if the same character repeats more than 1000 times
        var charCounts: [Character: Int] = [:]
        for char in text {
            charCounts[char, default: 0] += 1
            if charCounts[char]! > 1000 {
                return true
            }
        }
        
        return false
    }
}

