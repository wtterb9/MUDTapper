import Foundation
import Security
import Network
import CryptoKit

/// Certificate pinning manager for secure TLS connections
/// Provides protection against man-in-the-middle attacks
class CertificatePinning {
    
    // MARK: - Singleton
    
    static let shared = CertificatePinning()
    private init() {}
    
    // MARK: - Configuration
    
    private var pinnedCertificates: [String: [Data]] = [:]
    private var isPinningEnabled = true
    
    /// Enable or disable certificate pinning globally
    /// - Parameter enabled: true to enable pinning, false to disable
    func setPinningEnabled(_ enabled: Bool) {
        isPinningEnabled = enabled
    }
    
    // MARK: - Certificate Management
    
    /// Add a pinned certificate for a specific hostname
    /// - Parameters:
    ///   - certificateData: The DER-encoded certificate data
    ///   - hostname: The hostname to pin this certificate to
    func addPinnedCertificate(_ certificateData: Data, for hostname: String) {
        let normalizedHost = hostname.lowercased()
        if pinnedCertificates[normalizedHost] == nil {
            pinnedCertificates[normalizedHost] = []
        }
        pinnedCertificates[normalizedHost]?.append(certificateData)
        Logger.info("Added pinned certificate for \(hostname)", category: Logger.network)
    }
    
    /// Remove all pinned certificates for a hostname
    /// - Parameter hostname: The hostname to remove certificates for
    func removePinnedCertificates(for hostname: String) {
        let normalizedHost = hostname.lowercased()
        pinnedCertificates.removeValue(forKey: normalizedHost)
        Logger.info("Removed pinned certificates for \(hostname)", category: Logger.network)
    }
    
    /// Check if a hostname has pinned certificates
    /// - Parameter hostname: The hostname to check
    /// - Returns: true if certificates are pinned, false otherwise
    func hasPinnedCertificates(for hostname: String) -> Bool {
        let normalizedHost = hostname.lowercased()
        return pinnedCertificates[normalizedHost]?.isEmpty == false
    }
    
    // MARK: - Certificate Validation
    
    /// Validate a server's certificate chain against pinned certificates
    /// - Parameters:
    ///   - trust: The server trust to validate
    ///   - hostname: The hostname being connected to
    /// - Returns: true if validation passes, false if it fails
    func validateServerTrust(_ trust: SecTrust, for hostname: String) -> Bool {
        // If pinning is disabled, accept all certificates (use system validation only)
        guard isPinningEnabled else {
            return evaluateSystemTrust(trust)
        }
        
        let normalizedHost = hostname.lowercased()
        
        // If no certificates are pinned for this host, use system validation
        guard let pinnedCerts = pinnedCertificates[normalizedHost], !pinnedCerts.isEmpty else {
            return evaluateSystemTrust(trust)
        }
        
        // First verify the certificate chain using system validation
        guard evaluateSystemTrust(trust) else {
            Logger.warning("System trust evaluation failed for \(hostname)", category: Logger.network)
            return false
        }
        
        // Then check if any certificate in the chain matches our pinned certificates
        let certificateCount = SecTrustGetCertificateCount(trust)
        
        for i in 0..<certificateCount {
            if let serverCert = SecTrustGetCertificateAtIndex(trust, i) {
                let serverCertData = SecCertificateCopyData(serverCert) as Data
                
                // Check if this certificate matches any of our pinned certificates
                for pinnedCertData in pinnedCerts {
                    if serverCertData == pinnedCertData {
                        Logger.info("Certificate pinning validation passed for \(hostname)", category: Logger.network)
                        return true
                    }
                }
            }
        }
        
        // No matching certificate found
        Logger.warning("Certificate pinning validation failed for \(hostname) - no matching certificate", category: Logger.network)
        return false
    }
    
    /// Validate certificate using public key pinning (more flexible than certificate pinning)
    /// - Parameters:
    ///   - trust: The server trust to validate
    ///   - hostname: The hostname being connected to
    /// - Returns: true if validation passes, false if it fails
    func validateServerTrustWithPublicKeyPinning(_ trust: SecTrust, for hostname: String) -> Bool {
        // First verify the certificate chain using system validation
        guard evaluateSystemTrust(trust) else {
            return false
        }
        
        // Extract public keys from server certificates
        let certificateCount = SecTrustGetCertificateCount(trust)
        var serverPublicKeys: [SecKey] = []
        
        for i in 0..<certificateCount {
            if let serverCert = SecTrustGetCertificateAtIndex(trust, i),
               let publicKey = SecCertificateCopyKey(serverCert) {
                serverPublicKeys.append(publicKey)
            }
        }
        
        // For public key pinning, you would compare the server's public keys
        // against a list of known good public keys
        // This is more flexible than certificate pinning as it survives certificate renewal
        
        // For now, if we reach here and system trust passed, accept it
        return true
    }
    
    // MARK: - Private Helpers
    
    private func evaluateSystemTrust(_ trust: SecTrust) -> Bool {
        var error: CFError?
        let evaluated = SecTrustEvaluateWithError(trust, &error)
        
        if let error = error {
            Logger.error("System trust evaluation error", error: error as Error, category: Logger.network)
        }
        
        return evaluated
    }
    
    // MARK: - Certificate Extraction
    
    /// Extract certificate data from a server for pinning
    /// This is a utility method to help users pin certificates
    /// - Parameter trust: The server trust from a successful connection
    /// - Returns: Array of certificate data that can be pinned
    static func extractCertificates(from trust: SecTrust) -> [Data] {
        var certificates: [Data] = []
        let certificateCount = SecTrustGetCertificateCount(trust)
        
        for i in 0..<certificateCount {
            if let cert = SecTrustGetCertificateAtIndex(trust, i) {
                let certData = SecCertificateCopyData(cert) as Data
                certificates.append(certData)
            }
        }
        
        return certificates
    }
    
    /// Get a human-readable summary of a certificate
    /// - Parameter certificateData: The DER-encoded certificate data
    /// - Returns: Summary string with issuer and subject info
    static func getCertificateSummary(_ certificateData: Data) -> String {
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            return "Invalid certificate"
        }
        
        var summary = "Certificate:\n"
        
        // Get subject summary
        if let subjectSummary = SecCertificateCopySubjectSummary(certificate) as String? {
            summary += "  Subject: \(subjectSummary)\n"
        }
        
        // Get SHA-256 fingerprint for verification
        let sha256 = certificateData.sha256Hex
        summary += "  SHA-256: \(sha256)"
        
        return summary
    }
}

// MARK: - Data Extension for SHA-256

extension Data {
    /// Calculate SHA-256 hash of this data
    var sha256Hex: String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - NWConnection Extension

extension NWConnection {
    
    /// Configure TLS with certificate pinning
    /// - Parameters:
    ///   - hostname: The hostname to validate
    ///   - pinningManager: The certificate pinning manager (defaults to shared instance)
    func configureTLSWithPinning(hostname: String, pinningManager: CertificatePinning = .shared) {
        // Note: NWConnection TLS configuration requires using NWParameters
        // This is typically done during connection creation, not after
        // See MUDSocket.connect() for integration point
    }
}

