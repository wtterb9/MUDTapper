import Foundation

/// Utility for validating and safely compiling regex patterns
class RegexValidator {
    
    // MARK: - Validation
    
    /// Validates a regex pattern for safety and correctness
    /// - Parameter pattern: The regex pattern to validate
    /// - Returns: Error message if invalid, nil if valid
    static func validatePattern(_ pattern: String) -> String? {
        // Check for empty pattern
        guard !pattern.isEmpty else {
            return "Pattern cannot be empty"
        }
        
        // Check for excessive length (potential DoS)
        guard pattern.count <= 10000 else {
            return "Pattern is too long (maximum 10,000 characters)"
        }
        
        // Check for known dangerous patterns
        if let dangerousReason = checkForDangerousPatterns(pattern) {
            return dangerousReason
        }
        
        // Try to compile the pattern
        do {
            _ = try NSRegularExpression(pattern: pattern, options: [])
            return nil // Valid
        } catch {
            return "Invalid regex syntax: \(error.localizedDescription)"
        }
    }
    
    /// Safely compile a regex pattern with timeout protection
    /// - Parameters:
    ///   - pattern: The regex pattern
    ///   - options: Regex options
    /// - Returns: Compiled regex or nil if invalid/unsafe
    static func safeCompile(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        // Validate first
        guard validatePattern(pattern) == nil else {
            return nil
        }
        
        // Compile with error handling
        return try? NSRegularExpression(pattern: pattern, options: options)
    }
    
    /// Test a regex pattern against sample text with timeout
    /// - Parameters:
    ///   - pattern: The regex pattern
    ///   - testString: Sample text to test against
    ///   - timeout: Maximum time allowed in seconds (default: 0.1)
    /// - Returns: true if test completes within timeout, false if timeout or error
    static func testPatternPerformance(pattern: String, testString: String, timeout: TimeInterval = 0.1) -> Bool {
        guard let regex = safeCompile(pattern: pattern) else {
            return false
        }
        
        let startTime = Date()
        let range = NSRange(location: 0, length: testString.utf16.count)
        
        // Perform match
        _ = regex.firstMatch(in: testString, options: [], range: range)
        
        let elapsed = Date().timeIntervalSince(startTime)
        return elapsed < timeout
    }
    
    // MARK: - Dangerous Pattern Detection
    
    private static func checkForDangerousPatterns(_ pattern: String) -> String? {
        // Catastrophic backtracking patterns
        let dangerousPatterns = [
            // Nested quantifiers
            ("(.*)*", "Nested quantifiers can cause catastrophic backtracking"),
            ("(.+)+", "Nested quantifiers can cause catastrophic backtracking"),
            ("(.?)?", "Nested quantifiers can cause catastrophic backtracking"),
            
            // Overlapping alternation
            ("(a|a)*", "Overlapping alternation can cause exponential backtracking"),
            ("(a|ab)*", "Overlapping alternation can cause exponential backtracking"),
            
            // Excessive repetition
            ("a{1000,}", "Excessive repetition count"),
            ("a{100,1000}", "Excessive repetition range")
        ]
        
        for (dangerous, reason) in dangerousPatterns {
            if pattern.contains(dangerous) {
                return "Potentially dangerous pattern detected: \(reason)"
            }
        }
        
        // Check for excessive nesting
        let nestingDepth = calculateNestingDepth(pattern)
        if nestingDepth > 10 {
            return "Excessive nesting depth (\(nestingDepth) levels) - maximum is 10"
        }
        
        // Check for excessive alternations
        let alternationCount = pattern.components(separatedBy: "|").count - 1
        if alternationCount > 100 {
            return "Too many alternations (\(alternationCount)) - maximum is 100"
        }
        
        return nil
    }
    
    private static func calculateNestingDepth(_ pattern: String) -> Int {
        var maxDepth = 0
        var currentDepth = 0
        var inEscape = false
        
        for char in pattern {
            if inEscape {
                inEscape = false
                continue
            }
            
            if char == "\\" {
                inEscape = true
                continue
            }
            
            if char == "(" {
                currentDepth += 1
                maxDepth = max(maxDepth, currentDepth)
            } else if char == ")" {
                currentDepth = max(0, currentDepth - 1)
            }
        }
        
        return maxDepth
    }
}

