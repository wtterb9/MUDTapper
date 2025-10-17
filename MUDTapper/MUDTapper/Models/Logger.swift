import Foundation
import os.log

/// Centralized logging utility using OSLog for better performance and integration
class Logger {
    
    // MARK: - Log Categories
    
    static let network = OSLog(subsystem: "com.mudtapper", category: "Network")
    static let coreData = OSLog(subsystem: "com.mudtapper", category: "CoreData")
    static let ui = OSLog(subsystem: "com.mudtapper", category: "UI")
    static let automation = OSLog(subsystem: "com.mudtapper", category: "Automation")
    static let connection = OSLog(subsystem: "com.mudtapper", category: "Connection")
    static let general = OSLog(subsystem: "com.mudtapper", category: "General")
    
    // MARK: - Convenience Methods
    
    /// Log a debug message
    static func debug(_ message: String, category: OSLog, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let filename = (file as NSString).lastPathComponent
        os_log(.debug, log: category, "%{public}@:%d %{public}@() - %{public}@", filename, line, function, message)
        #endif
    }
    
    /// Log an info message
    static func info(_ message: String, category: OSLog) {
        os_log(.info, log: category, "%{public}@", message)
    }
    
    /// Log a warning
    static func warning(_ message: String, category: OSLog, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        os_log(.error, log: category, "⚠️ %{public}@:%d %{public}@() - %{public}@", filename, line, function, message)
    }
    
    /// Log an error
    static func error(_ message: String, error: Error? = nil, category: OSLog, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        if let error = error {
            os_log(.error, log: category, "❌ %{public}@:%d %{public}@() - %{public}@ | Error: %{public}@", filename, line, function, message, error.localizedDescription)
        } else {
            os_log(.error, log: category, "❌ %{public}@:%d %{public}@() - %{public}@", filename, line, function, message)
        }
    }
    
    /// Log a fault (critical error)
    static func fault(_ message: String, error: Error? = nil, category: OSLog, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = (file as NSString).lastPathComponent
        if let error = error {
            os_log(.fault, log: category, "💥 %{public}@:%d %{public}@() - %{public}@ | Error: %{public}@", filename, line, function, message, error.localizedDescription)
        } else {
            os_log(.fault, log: category, "💥 %{public}@:%d %{public}@() - %{public}@", filename, line, function, message)
        }
    }
    
    // MARK: - Network Logging
    
    static func logConnection(_ message: String) {
        info(message, category: connection)
    }
    
    static func logNetworkData(_ message: String) {
        debug(message, category: network)
    }
    
    static func logNetworkError(_ message: String, error: Error? = nil) {
        self.error(message, error: error, category: network)
    }
    
    // MARK: - Core Data Logging
    
    static func logCoreDataOperation(_ message: String) {
        debug(message, category: coreData)
    }
    
    static func logCoreDataError(_ message: String, error: Error? = nil) {
        self.error(message, error: error, category: coreData)
    }
    
    // MARK: - Automation Logging
    
    static func logTrigger(_ message: String) {
        debug(message, category: automation)
    }
    
    static func logAlias(_ message: String) {
        debug(message, category: automation)
    }
    
    // MARK: - UI Logging
    
    static func logUIEvent(_ message: String) {
        debug(message, category: ui)
    }
}

