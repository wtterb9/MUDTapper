import Foundation
import Security

/// Secure storage manager using iOS Keychain for sensitive data like passwords
class KeychainManager {
    
    static let shared = KeychainManager()
    private init() {}
    
    // MARK: - Service Identifier
    
    private let service = "com.mudtapper.passwords"
    
    // MARK: - Error Types
    
    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case invalidData
        case unhandledError(status: OSStatus)
        
        var localizedDescription: String {
            switch self {
            case .duplicateItem:
                return "Item already exists in keychain"
            case .itemNotFound:
                return "Item not found in keychain"
            case .invalidData:
                return "Invalid data format"
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
    
    // MARK: - Save Password
    
    /// Save a password for a given world identifier
    /// - Parameters:
    ///   - password: The password to store
    ///   - account: The account identifier (use world's objectID.uriRepresentation().absoluteString)
    /// - Throws: KeychainError if save fails
    func savePassword(_ password: String, for account: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Check if item already exists
        let existingItemQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        // Try to update existing item first
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]
        
        let updateStatus = SecItemUpdate(existingItemQuery as CFDictionary, attributes as CFDictionary)
        
        if updateStatus == errSecSuccess {
            return // Successfully updated
        } else if updateStatus == errSecItemNotFound {
            // Item doesn't exist, create new one
            let newItem: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: addStatus)
            }
        } else {
            throw KeychainError.unhandledError(status: updateStatus)
        }
    }
    
    // MARK: - Retrieve Password
    
    /// Retrieve a password for a given world identifier
    /// - Parameter account: The account identifier
    /// - Returns: The password string, or nil if not found
    func getPassword(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    // MARK: - Delete Password
    
    /// Delete a password for a given world identifier
    /// - Parameter account: The account identifier
    /// - Throws: KeychainError if deletion fails
    func deletePassword(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Success or item not found are both acceptable outcomes for deletion
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    // MARK: - Update Password
    
    /// Update an existing password
    /// - Parameters:
    ///   - password: The new password
    ///   - account: The account identifier
    /// - Throws: KeychainError if update fails
    func updatePassword(_ password: String, for account: String) throws {
        // savePassword handles both create and update
        try savePassword(password, for: account)
    }
    
    // MARK: - Check Password Exists
    
    /// Check if a password exists for a given account
    /// - Parameter account: The account identifier
    /// - Returns: true if password exists, false otherwise
    func passwordExists(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Migration Support
    
    /// Migrate passwords from Core Data to Keychain
    /// This should be called once during app upgrade
    func migratePasswordsFromCoreData() {
        let context = PersistenceController.shared.viewContext
        let request = World.fetchRequest()
        request.predicate = NSPredicate(format: "password != nil AND password != ''")
        
        do {
            let worldsWithPasswords = try context.fetch(request)
            
            for world in worldsWithPasswords {
                guard let password = world.password,
                      !password.isEmpty else { continue }
                
                let accountKey = world.objectID.uriRepresentation().absoluteString
                
                // Save to keychain
                try? savePassword(password, for: accountKey)
                
                // Clear from Core Data
                world.password = nil
            }
            
            // Save context to persist the password clearing
            if context.hasChanges {
                try context.save()
            }
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: "KeychainMigrationCompleted")
            
            print("KeychainManager: Successfully migrated \(worldsWithPasswords.count) passwords to Keychain")
        } catch {
            print("KeychainManager: Error migrating passwords: \(error)")
        }
    }
    
    // MARK: - Clear All Passwords (for testing/reset)
    
    /// Clear all passwords stored by this app
    /// WARNING: This is destructive and cannot be undone
    func clearAllPasswords() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

// MARK: - World Extension for Keychain Integration

extension World {
    
    /// Get the password for this world from Keychain
    var securePassword: String? {
        let accountKey = objectID.uriRepresentation().absoluteString
        return KeychainManager.shared.getPassword(for: accountKey)
    }
    
    /// Set the password for this world in Keychain
    func setSecurePassword(_ password: String?) throws {
        let accountKey = objectID.uriRepresentation().absoluteString
        
        if let password = password, !password.isEmpty {
            try KeychainManager.shared.savePassword(password, for: accountKey)
        } else {
            // Delete password if nil or empty
            try KeychainManager.shared.deletePassword(for: accountKey)
        }
        
        // Clear the Core Data password field if it still has data
        if self.password != nil {
            self.password = nil
            try? managedObjectContext?.save()
        }
    }
    
    /// Check if this world has a password stored in Keychain
    var hasSecurePassword: Bool {
        let accountKey = objectID.uriRepresentation().absoluteString
        return KeychainManager.shared.passwordExists(for: accountKey)
    }
}

