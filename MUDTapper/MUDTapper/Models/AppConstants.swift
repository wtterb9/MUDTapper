import Foundation
import CoreData

/// Centralized application constants
enum AppConstants {
    
    // MARK: - Network Constants
    
    enum Network {
        static let defaultTelnetPort: Int32 = 23
        static let defaultConnectionTimeout: TimeInterval = 30.0
        static let keepAliveInterval: TimeInterval = 30.0
        static let backgroundKeepAliveInterval: TimeInterval = 10.0
        static let reconnectDelay: TimeInterval = 2.0
        static let maxReconnectAttempts = Int.max
        
        // Port validation
        static let minPort = 1
        static let maxPort = 65535
        static let privilegedPortThreshold = 1024
        
        // Socket timeouts
        static let tcpKeepAliveIdle: Int = 15
        static let tcpKeepAliveInterval: Int = 5
        static let tcpKeepAliveCount: Int = 6
        static let connectionTimeout: Int = 30
    }
    
    // MARK: - UI Constants
    
    enum UI {
        // Layout
        static let tabBarHeight: CGFloat = 36
        static let sideMenuWidth: CGFloat = 300
        static let sideMenuSwipeActivationEdgeWidth: CGFloat = 20
        static let sideMenuOpenTranslationThreshold: CGFloat = 150
        static let sideMenuDimAlpha: CGFloat = 0.7
        
        // Animation durations
        static let keyboardMaxDuration: Double = 0.15
        static let sideMenuAnimationDuration: Double = 0.3
        static let dragEndAnimationDuration: Double = 0.2
        static let tabBarLongPressDuration: Double = 0.8
        
        // Radial controls
        static let radialButtonMinSize: CGFloat = 80
        static let radialButtonMaxSize: CGFloat = 120
        static let radialButtonSizePercent: CGFloat = 0.15 // 15% of screen
        static let radialButtonMarginPercent: CGFloat = 0.048 // 4.8% of screen
        static let radialButtonMinMargin: CGFloat = 34
    }
    
    // MARK: - Data Constants
    
    enum Data {
        // Buffer limits
        static let maxTextBufferLength = 50000
        static let maxCommandHistorySize = 100
        
        // File sizes
        static let maxLogFileSize: Int64 = 50 * 1024 * 1024 // 50MB
        
        // Timers
        static let minFlushInterval: TimeInterval = 0.02
        static let maxFlushInterval: TimeInterval = 0.12
    }
    
    // MARK: - Automation Constants
    
    enum Automation {
        static let defaultTriggerPriority: Int32 = 50
        static let defaultTickerInterval: Double = 60.0
        
        // Limits
        static let maxUniqueNameAttempts = 1000
    }
    
    // MARK: - Background Task Constants
    
    enum Background {
        static let connectionMaintenanceTaskName = "MUDSocket-ConnectionMaintenance"
        static let voipProtectionTaskName = "MUDSocket-VoIP-Protection"
        static let silentAudioMaintenanceTaskName = "SilentAudio-Maintenance"
        
        static let backgroundTimeWarningThreshold: TimeInterval = 60
        static let backgroundTimeCriticalThreshold: TimeInterval = 30
        
        static let connectionLossDetectionInterval: TimeInterval = 15.0
        static let backgroundTaskChainInterval: TimeInterval = 25.0
        static let backgroundTimeMonitorInterval: TimeInterval = 5.0
    }
    
    // MARK: - Feature Flags
    
    enum Features {
        static let gmcpEnabled = true
        static let msdpEnabled = true
        static let mccpEnabled = true
        static let autoReconnectEnabled = true
    }
}

