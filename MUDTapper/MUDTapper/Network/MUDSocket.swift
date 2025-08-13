import Foundation
import Network
import SystemConfiguration
import UIKit
import AVFoundation
import Compression

protocol MUDSocketDelegate: AnyObject {
    func mudSocket(_ socket: MUDSocket, didConnectToHost host: String, port: UInt16)
    func mudSocket(_ socket: MUDSocket, didDisconnectWithError error: Error?)
    func mudSocket(_ socket: MUDSocket, didReceiveData data: Data)
    func mudSocket(_ socket: MUDSocket, didWriteDataWithTag tag: Int)
    func mudSocket(_ socket: MUDSocket, didUpdateLatencyMs latencyMs: Int)
}


class MUDSocket: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: MUDSocketDelegate?
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.mudtapper.socket", qos: .userInitiated)
    private var keepAliveTimer: Timer?
    private var reconnectTimer: Timer?
    private var lastActivityTime: Date = Date()
    private var isInBackground = false
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = Int.max
    private let reconnectDelay: TimeInterval = 2.0
    
    // Background task management
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundKeepAliveTimer: Timer?
    private var connectionMaintenanceTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTaskStartTime: Date?
    private var voipBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Enhanced background connection maintenance
    private var connectionLossDetectionTimer: Timer?
    private var lastDataReceiveTime: Date = Date()
    private var consecutiveKeepAliveFailures = 0
    private var backgroundTaskChainTimer: Timer?
    private var isInDeepBackground = false
    private var pathMonitor: NWPathMonitor?
    
    // Network reachability monitoring
    private var reachability: SCNetworkReachability?
    private var lastNetworkStatus: SCNetworkReachabilityFlags?
    private var isMonitoringNetwork = false
    
    // VoIP socket support for enhanced background protection
    private var isVoIPSocketEnabled = false
    private var voipSocket: CFSocket?
    private var voipSocketSource: CFRunLoopSource?
    
    // Connection state tracking
    private var lastSuccessfulDataTime: Date = Date()
    private var connectionHealthCheckTimer: Timer?
    
    // Connection persistence scoring
    private var connectionQualityScore: Int = 100  // Start with perfect score
    private var backgroundSuccessfulKeepalives: Int = 0
    private var backgroundFailedKeepalives: Int = 0
    
    var isConnected: Bool {
        return connection?.state == .ready
    }
    
    var connectionState: NWConnection.State? {
        return connection?.state
    }
    
    var connectedHost: String?
    var connectedPort: UInt16 = 0
    // Identify owning world for cross-session vitals updates
    var currentWorldObjectID: NSManagedObjectID?
    
    // Telnet feature flags and state
    private var gmcpEnabled: Bool = NetworkingPreferences.gmcpEnabled
    private var msdpEnabled: Bool = NetworkingPreferences.msdpEnabled
    
    // MCCP (compression) state
    private var mccpActive: Bool = false
    private var decompressionStream: compression_stream?
    private var decompressionStreamInitialized: Bool = false
    
    // Latency probe
    private var latencyProbeSentAt: Date?
    private var awaitingLatencyProbe: Bool = false
    private(set) var lastLatencyMs: Int = 0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupAppStateNotifications()
    }
    
    deinit {
        disconnect()
        NotificationCenter.default.removeObserver(self)
        stopNetworkMonitoring()
        stopPathMonitoring()
        endConnectionMaintenanceTask()
        endBackgroundTask()
        disableVoIPBackgroundProtection()
    }
    
    // MARK: - MSDP Support
    
    /// Send an MSDP variable to the server
    /// - Parameters:
    ///   - variable: The MSDP variable name (e.g., "XTERM_256_COLORS")
    ///   - value: The value to send (e.g., "1")
    func sendMSDP(variable: String, value: String) {
        guard connection?.state == .ready else {
            print("MUDSocket: Cannot send MSDP - connection not ready")
            return
        }
        
        // MSDP format: IAC SB MSDP variable MSDP_VAL value IAC SE
        var msdpData: [UInt8] = [
            255, 250, 69, // IAC SB MSDP
        ]
        
        // Add variable name
        msdpData.append(contentsOf: variable.utf8)
        
        // Add MSDP_VAL separator
        msdpData.append(1) // MSDP_VAL
        
        // Add value
        msdpData.append(contentsOf: value.utf8)
        
        // Add IAC SE
        msdpData.append(contentsOf: [255, 240]) // IAC SE
        
        let data = Data(msdpData)
        
        // Debug logging
        print("MUDSocket: Sending MSDP \(variable)=\(value)")
        print("MUDSocket: MSDP bytes: \(msdpData.map { String(format: "%02x", $0) }.joined(separator: " "))")
        print("MUDSocket: MSDP data length: \(data.count) bytes")
        
        // Log the actual bytes being sent
        let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("MUDSocket: Raw MSDP data: \(hexString)")
        
        send(data)
    }
    
    /// Send XTERM_256_COLORS=1 to enable 256-color support
    func sendXterm256Colors() {
        sendMSDP(variable: "XTERM_256_COLORS", value: "1")
    }

    // MARK: - Connection Management
    
    func connect(to hostname: String, port: UInt16, timeout: TimeInterval = 30.0) throws {
        guard !hostname.isEmpty else {
            throw MUDSocketError.invalidHostname
        }
        
        guard port > 0 else {
            throw MUDSocketError.invalidPort
        }
        
        // Validate hostname format
        guard isValidHostname(hostname) else {
            throw MUDSocketError.invalidHostname
        }
        
        print("MUDSocket: Attempting to connect to \(hostname):\(port)")
        
        if connection != nil {
            disconnect()
        }
        
        let host = NWEndpoint.Host(hostname)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        
        // Create enhanced connection parameters for MUD client
        let parameters = NWParameters.tcp
        
        // Configure for interactive, low-latency communication
        parameters.serviceClass = .interactiveVoice
        parameters.multipathServiceType = .interactive
        // Allow any interface (WiFi or Cellular). Do not restrict interface type.
        
        // Configure TCP options for MUD gaming
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 15      // Start keep-alive after 15s of inactivity (was 30s)
            tcpOptions.keepaliveInterval = 5   // Send keep-alive every 5s (was 10s)
            tcpOptions.keepaliveCount = 6      // Allow 6 failed keep-alives before considering dead (was 3)
            tcpOptions.noDelay = true          // Disable Nagle's algorithm for low latency
            tcpOptions.connectionTimeout = 30  // 30 second connection timeout
            
            // Add more aggressive socket options for background stability
            tcpOptions.enableFastOpen = false  // Disable TCP Fast Open for stability
            tcpOptions.disableAckStretching = true  // Prevent delayed ACKs for real-time gaming
        }
        
        connection = NWConnection(host: host, port: nwPort, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            self?.handleStateUpdate(state)
        }
        
        connection?.start(queue: queue)
        
        connectedHost = hostname
        connectedPort = port
        shouldReconnect = NetworkingPreferences.autoReconnectEnabled
        reconnectAttempts = 0
        
        // Enable VoIP background protection for persistent connection
        enableVoIPBackgroundProtection()
        
        // Start network monitoring
        setupNetworkMonitoring()
        startPathMonitoring()
        
        #if DEBUG
        print("MUDSocket: Connection started, waiting for state updates...")
        #endif
    }
    
    func disconnect() {
        // Clean up compression if active
        endDecompression()
        stopKeepAliveTimer()
        stopReconnectTimer()
        stopNetworkMonitoring()
        endConnectionMaintenanceTask()
        endBackgroundTask()
        disableVoIPBackgroundProtection()
        connection?.cancel()
        connection = nil
        connectedHost = nil
        connectedPort = 0
        shouldReconnect = false
        reconnectAttempts = 0
    }
    
    // MARK: - Data Transmission
    
    func send(_ text: String, encoding: String.Encoding = .utf8) {
        guard let connection = connection, connection.state == .ready else { return }
        
        var dataToSend = text
        
        // Normalize line endings to CRLF
        if dataToSend.hasSuffix("\r\n") {
            // already normalized
        } else if dataToSend.hasSuffix("\n") {
            dataToSend = String(dataToSend.dropLast()) + "\r\n"
        } else if dataToSend.isEmpty {
            dataToSend = "\r\n"
        } else {
            dataToSend += "\r\n"
        }
        
        guard let data = dataToSend.data(using: encoding) else {
            print("Failed to encode text: \(text)")
            return
        }
        
        send(data)
    }
    
    func send(_ data: Data) {
        guard let connection = connection, connection.state == .ready else { 
            print("MUDSocket: Cannot send data - connection not ready")
            return 
        }
        
        #if DEBUG
        print("MUDSocket: Sending \(data.count) bytes of data")
        #endif
        
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                if let error = error {
                    #if DEBUG
                    print("MUDSocket: Send error: \(error)")
                    #endif
                } else {
                    #if DEBUG
                    print("MUDSocket: Data sent successfully")
                    #endif
                    strongSelf.lastActivityTime = Date()
                    strongSelf.delegate?.mudSocket(strongSelf, didWriteDataWithTag: 0)
                }
            }
        })
    }
    
    // MARK: - Background App Handling
    
    private func setupAppStateNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: .appDidBecomeActive,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: .appDidEnterBackground,
            object: nil
        )
    }
    
    @objc private func handleAppDidBecomeActive() {
        isInBackground = false
        isInDeepBackground = false
        #if DEBUG
        print("MUDSocket: App became active")
        #endif
        
        // End all background tasks and timers
        endConnectionMaintenanceTask()
        endBackgroundTask()
        stopConnectionLossDetection()
        stopBackgroundTaskChaining()
        
        // Reset failure counters
        consecutiveKeepAliveFailures = 0
        
        // Check connection status and reconnect if needed
        if shouldReconnect && connectedHost != nil {
            if isConnected {
                #if DEBUG
                print("MUDSocket: Testing connection health after app resume")
                #endif
                testConnectionHealth { [weak self] isHealthy in
                    if isHealthy {
                        #if DEBUG
                        print("MUDSocket: Connection is healthy, resuming normal operation")
                        #endif
                        self?.startKeepAliveTimer()
                    } else {
                        #if DEBUG
                        print("MUDSocket: Connection is unhealthy, attempting reconnection")
                        #endif
                        self?.attemptReconnect()
                    }
                }
            } else {
                #if DEBUG
                print("MUDSocket: Not connected, attempting to reconnect after app became active")
                #endif
                attemptReconnect()
            }
        }
    }
    
    @objc private func handleAppDidEnterBackground() {
        isInBackground = true
        #if DEBUG
        print("MUDSocket: App entered background")
        #endif
        
        // Stop foreground keep-alive timer
        stopKeepAliveTimer()
        
        // Start comprehensive background protection for network connection
        if isConnected {
            startConnectionMaintenanceTask()
            
            // Send immediate keep-alive to ensure connection is still active
            sendKeepAlive()
            
            // Start connection loss detection
            startConnectionLossDetection()
            
            // Set up background task chaining for extended background time
            startBackgroundTaskChaining()
            
            #if DEBUG
            print("MUDSocket: Started comprehensive connection maintenance for background")
            #endif
        }
    }
    
    // MARK: - Keep-Alive and Reconnection
    
    private func startKeepAliveTimer() {
        stopKeepAliveTimer()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }
    
    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    private func sendKeepAlive() {
        // Send a simple keep-alive command (usually just a newline)
        // This prevents the server from timing out the connection
        guard isConnected else {
            print("MUDSocket: Cannot send keep-alive, not connected")
            return
        }
        
        print("MUDSocket: Sending keep-alive")
        lastActivityTime = Date()
        
        // Use different keep-alive strategies based on background state
        let keepAliveData: Data
        if isInBackground {
            // In background, use a more substantial keep-alive that might provoke a response
            if isInDeepBackground {
                // Deep background - use a command that should definitely get a response
                // Rotate between different commands to avoid server-side filtering
                let commands = ["look", "score", "time", "who"]
                let randomCommand = commands.randomElement() ?? "look"
                keepAliveData = "\(randomCommand)\n".data(using: .utf8) ?? "\n".data(using: .utf8)!
            } else {
                // Normal background - use a minimal but trackable command
                // Some MUDs respond to empty commands, others ignore them
                keepAliveData = " \n".data(using: .utf8) ?? "\n".data(using: .utf8)!
            }
        } else {
            // Foreground - just send a newline (most servers echo this or ignore silently)
            keepAliveData = "\n".data(using: .utf8)!
            // Mark as latency probe
            latencyProbeSentAt = Date()
            awaitingLatencyProbe = true
        }
        
        // Send with completion tracking for background failure detection
        connection?.send(content: keepAliveData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("MUDSocket: Keep-alive send failed: \(error)")
                if self?.isInBackground == true {
                    self?.consecutiveKeepAliveFailures += 1
                    self?.backgroundFailedKeepalives += 1
                    self?.updateConnectionQuality(success: false)
                    print("MUDSocket: Keep-alive failures: \(self?.consecutiveKeepAliveFailures ?? 0)")
                    
                    // If multiple failures in background, consider connection problematic
                    if self?.consecutiveKeepAliveFailures ?? 0 >= 2 {
                        print("MUDSocket: Multiple keep-alive failures, connection may be lost")
                        DispatchQueue.main.async {
                            self?.handleBackgroundConnectionLoss()
                        }
                    }
                }
            } else {
                print("MUDSocket: Keep-alive sent successfully")
                self?.consecutiveKeepAliveFailures = 0
                if self?.isInBackground == true {
                    self?.backgroundSuccessfulKeepalives += 1
                    self?.updateConnectionQuality(success: true)
                }
                // If this was a foreground latency probe and no immediate error, we wait for next data to compute latency
                if self?.isInBackground == false {
                    // no-op here; handled when data arrives
                }
            }
        })
    }
    
    private func attemptReconnect() {
        guard shouldReconnect && reconnectAttempts < maxReconnectAttempts else {
            print("MUDSocket: Max reconnection attempts reached or reconnection disabled")
            return
        }
        
        reconnectAttempts += 1
        #if DEBUG
        print("MUDSocket: Attempting reconnection \(reconnectAttempts)/\(maxReconnectAttempts)")
        #endif
        
        guard let host = connectedHost, connectedPort > 0 else {
            #if DEBUG
            print("MUDSocket: No connection info available for reconnection")
            #endif
            return
        }
        
        do {
            try connect(to: host, port: connectedPort)
        } catch {
            #if DEBUG
            print("MUDSocket: Reconnection failed: \(error)")
            #endif
            scheduleReconnectAttempt()
        }
    }
    
    private func scheduleReconnectAttempt() {
        stopReconnectTimer()
        let delay = min(2.0 * Double(reconnectAttempts), 10.0) // Exponential backoff, max 10 seconds
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptReconnect()
        }
    }
    
    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - Background Task Management
    
    private func startConnectionMaintenanceTask() {
        // End any existing tasks first
        endConnectionMaintenanceTask()
        endBackgroundTask()
        
        #if DEBUG
        print("MUDSocket: Starting connection maintenance task")
        #endif
        backgroundTaskStartTime = Date()
        
        connectionMaintenanceTask = UIApplication.shared.beginBackgroundTask(withName: "MUDSocket-ConnectionMaintenance") { [weak self] in
            #if DEBUG
            print("MUDSocket: Connection maintenance task expired")
            #endif
            self?.handleBackgroundTaskExpiration()
        }
        
        if connectionMaintenanceTask == .invalid {
            #if DEBUG
            print("MUDSocket: Failed to start connection maintenance task")
            #endif
            return
        }
        
        #if DEBUG
        print("MUDSocket: Connection maintenance task started with ID: \(connectionMaintenanceTask.rawValue)")
        #endif
        
        // Start aggressive background keep-alive
        startBackgroundKeepAlive(interval: getAdaptiveKeepAliveInterval())
        
        // Monitor background time remaining
        startBackgroundTimeMonitoring()
    }
    
    private func endConnectionMaintenanceTask() {
        guard connectionMaintenanceTask != .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Ending connection maintenance task")
        #endif
        stopBackgroundKeepAlive()
        stopBackgroundTimeMonitoring()
        
        UIApplication.shared.endBackgroundTask(connectionMaintenanceTask)
        connectionMaintenanceTask = .invalid
        backgroundTaskStartTime = nil
    }
    
    private func handleBackgroundTaskExpiration() {
        #if DEBUG
        print("MUDSocket: Background task expiring - implementing graceful degradation")
        #endif
        
        // This is called when iOS is about to suspend the app
        // We need to handle this quickly to avoid being killed by the watchdog
        
        // Stop all timers immediately
        stopBackgroundKeepAlive()
        stopBackgroundTimeMonitoring()
        
        if isConnected {
            // Send a final keep-alive if possible (non-blocking)
            #if DEBUG
            print("MUDSocket: Sending final keep-alive before suspension")
            #endif
            sendKeepAlive()
            
            // Note: We deliberately do NOT disconnect here
            // The connection will be tested when the app resumes
            // This allows for quick recovery if the suspension was brief
        }
        
        // End the task
        endConnectionMaintenanceTask()
    }
    
    private func startBackgroundTimeMonitoring() {
        // Monitor remaining background time and adapt strategy
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
            let taskDuration = self.backgroundTaskStartTime?.timeIntervalSinceNow ?? 0
            
            #if DEBUG
            print("MUDSocket: Background time remaining: \(backgroundTimeRemaining)s, task duration: \(-taskDuration)s")
            #endif
            
            // If we're running low on time, reduce keep-alive frequency
            if backgroundTimeRemaining < 30 {
                #if DEBUG
                print("MUDSocket: Low background time remaining, reducing keep-alive frequency")
                #endif
                self.stopBackgroundKeepAlive()
                // Send one final keep-alive
                self.sendKeepAlive()
                timer.invalidate()
            } else if backgroundTimeRemaining < 60 {
                // Reduce frequency to every 20 seconds
                self.stopBackgroundKeepAlive()
                self.startBackgroundKeepAlive(interval: 20.0)
            }
            
            // Stop monitoring if task is no longer valid
            if self.connectionMaintenanceTask == .invalid {
                timer.invalidate()
            }
        }
    }
    
    private func stopBackgroundTimeMonitoring() {
        // Timer will be invalidated by the monitoring logic itself
    }
    
    private func startBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Starting legacy background task")
        #endif
        backgroundTask = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
            #if DEBUG
            print("MUDSocket: Legacy background task expired")
            #endif
            self?.endBackgroundTask()
        })
        
        if backgroundTask == .invalid {
            #if DEBUG
            print("MUDSocket: Failed to start legacy background task")
            #endif
        }
    }
    
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Ending legacy background task")
        #endif
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
    
    private func startBackgroundKeepAlive(interval: TimeInterval = 10.0) {
        stopBackgroundKeepAlive()
        
        #if DEBUG
        print("MUDSocket: Starting background keep-alive with \(interval)s interval")
        #endif
        
        // Send keep-alive every specified interval in background
        backgroundKeepAliveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.isConnected {
                #if DEBUG
                print("MUDSocket: Sending background keep-alive")
                #endif
                self.sendKeepAlive()
                
                // Adaptive frequency based on background time remaining
                let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
                if backgroundTimeRemaining < 60 && interval < 15.0 {
                    // If we're running low on background time, reduce frequency
                    #if DEBUG
                    print("MUDSocket: Reducing keep-alive frequency due to limited background time")
                    #endif
                    self.stopBackgroundKeepAlive()
                    self.startBackgroundKeepAlive(interval: 15.0)
                } else if backgroundTimeRemaining > 120 && interval > 8.0 {
                    // If we have plenty of background time, increase frequency
                    #if DEBUG
                    print("MUDSocket: Increasing keep-alive frequency with abundant background time")
                    #endif
                    self.stopBackgroundKeepAlive()
                    self.startBackgroundKeepAlive(interval: 8.0)
                }
            } else {
                #if DEBUG
                print("MUDSocket: Not connected, stopping background keep-alive")
                #endif
                self.stopBackgroundKeepAlive()
            }
        }
    }
    
    private func stopBackgroundKeepAlive() {
        backgroundKeepAliveTimer?.invalidate()
        backgroundKeepAliveTimer = nil
    }
    
    // MARK: - Network Reachability Monitoring
    
    private func setupNetworkMonitoring() {
        guard let host = connectedHost, !isMonitoringNetwork else { return }
        
        #if DEBUG
        print("MUDSocket: Setting up network monitoring for \(host)")
        #endif
        
        // Create reachability reference
        reachability = SCNetworkReachabilityCreateWithName(nil, host)
        
        guard let reachability = reachability else {
            #if DEBUG
            print("MUDSocket: Failed to create reachability reference")
            #endif
            return
        }
        
        // Set up callback
        var context = SCNetworkReachabilityContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        
        let callback: SCNetworkReachabilityCallBack = { (reachability, flags, info) in
            guard let info = info else { return }
            let socket = Unmanaged<MUDSocket>.fromOpaque(info).takeUnretainedValue()
            socket.handleNetworkChange(flags: flags)
        }
        
        if SCNetworkReachabilitySetCallback(reachability, callback, &context) {
            if SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                isMonitoringNetwork = true
                #if DEBUG
                print("MUDSocket: Network monitoring started")
                #endif
                
                // Get initial status
                var flags = SCNetworkReachabilityFlags()
                if SCNetworkReachabilityGetFlags(reachability, &flags) {
                    lastNetworkStatus = flags
                    #if DEBUG
                    print("MUDSocket: Initial network status: \(flags)")
                    #endif
                }
            } else {
                #if DEBUG
                print("MUDSocket: Failed to schedule network monitoring")
                #endif
            }
        } else {
            #if DEBUG
            print("MUDSocket: Failed to set network monitoring callback")
            #endif
        }
    }
    
    private func stopNetworkMonitoring() {
        guard let reachability = reachability, isMonitoringNetwork else { return }
        
        SCNetworkReachabilityUnscheduleFromRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.reachability = nil
        isMonitoringNetwork = false
        lastNetworkStatus = nil
        #if DEBUG
        print("MUDSocket: Network monitoring stopped")
        #endif
    }
    
    // MARK: - NWPath monitoring
    private func startPathMonitoring() {
        stopPathMonitoring()
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            #if DEBUG
            print("MUDSocket: NWPath update: status=\(path.status), expensive=\(path.isExpensive), constrained=\(path.isConstrained)")
            #endif
            if path.status == .satisfied {
                if self.shouldReconnect && !self.isConnected {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.attemptReconnect()
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
    
    private func stopPathMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
    
    private func handleNetworkChange(flags: SCNetworkReachabilityFlags) {
        #if DEBUG
        print("MUDSocket: Network status changed: \(flags)")
        #endif
        
        let wasReachable = lastNetworkStatus?.contains(.reachable) ?? false
        let isReachable = flags.contains(.reachable)
        
        // Check if network interface changed (WiFi to cellular or vice versa)
        let interfaceChanged = lastNetworkStatus != nil && lastNetworkStatus != flags
        
        // Log network interface type
        let interfaceType = getNetworkInterfaceType(flags: flags)
        #if DEBUG
        print("MUDSocket: Current network interface: \(interfaceType)")
        #endif
        
        lastNetworkStatus = flags
        
        if interfaceChanged {
            #if DEBUG
            print("MUDSocket: Network interface changed, connection may be affected")
            #endif
            
            // If we were connected and network interface changed, attempt reconnection
            if isConnected && isReachable {
                #if DEBUG
                print("MUDSocket: Network interface changed, attempting reconnection")
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.attemptReconnectionAfterNetworkChange()
                }
            }
        }
        
        if !wasReachable && isReachable {
            #if DEBUG
            print("MUDSocket: Network became reachable")
            #endif
            // Network became available, try to reconnect if we should be connected
            if shouldReconnect && !isConnected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.attemptReconnect()
                }
            }
        } else if wasReachable && !isReachable {
            #if DEBUG
            print("MUDSocket: Network became unreachable")
            #endif
            // Network became unavailable, this will be handled by connection failure
        }
    }
    
    private func getNetworkInterfaceType(flags: SCNetworkReachabilityFlags) -> String {
        if flags.contains(.isWWAN) {
            return "Cellular"
        } else if flags.contains(.reachable) {
            return "WiFi"
        } else {
            return "None"
        }
    }
    
    private func attemptReconnectionAfterNetworkChange() {
        guard shouldReconnect && connectedHost != nil else { return }
        
        #if DEBUG
        print("MUDSocket: Attempting reconnection after network interface change")
        #endif
        
        // Force disconnect current connection
        connection?.cancel()
        connection = nil
        
        // Reset reconnection attempts for network change
        reconnectAttempts = 0
        
        // Attempt to reconnect
        attemptReconnect()
    }
    
    // MARK: - VoIP Socket Configuration
    
    /// Enable VoIP socket protection for background operation
    /// This provides the strongest background protection available on iOS
    func enableVoIPBackgroundProtection() {
        guard !isVoIPSocketEnabled else { return }
        
        #if DEBUG
        print("MUDSocket: Enabling VoIP background protection")
        #endif
        isVoIPSocketEnabled = true
        
        // Start VoIP background task
        startVoIPBackgroundTask()
        
        // Configure connection for VoIP if already connected
        if let connection = self.connection {
            configureConnectionForVoIP(connection)
        }
    }
    
    /// Disable VoIP socket protection
    func disableVoIPBackgroundProtection() {
        guard isVoIPSocketEnabled else { return }
        
        #if DEBUG
        print("MUDSocket: Disabling VoIP background protection")
        #endif
        isVoIPSocketEnabled = false
        
        cleanupVoIPSocket()
        endVoIPBackgroundTask()
    }
    
    private func configureConnectionForVoIP(_ connection: NWConnection) {
        // Configure connection parameters for VoIP
        let parameters = NWParameters.tcp
        parameters.serviceClass = .interactiveVoice
        parameters.multipathServiceType = .interactive
        
        // Enable keep-alive at the TCP level
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 30
            tcpOptions.keepaliveInterval = 10
            tcpOptions.keepaliveCount = 3
            tcpOptions.noDelay = true
        }
        
        #if DEBUG
        print("MUDSocket: Configured connection for VoIP operation")
        #endif
    }
    
    private func startVoIPBackgroundTask() {
        endVoIPBackgroundTask() // Clean up any existing task
        
        #if DEBUG
        print("MUDSocket: Starting VoIP background task")
        #endif
        voipBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MUDSocket-VoIP-Protection") { [weak self] in
            #if DEBUG
            print("MUDSocket: VoIP background task expired")
            #endif
            self?.handleVoIPBackgroundTaskExpiration()
        }
        
        if voipBackgroundTask == .invalid {
            #if DEBUG
            print("MUDSocket: Failed to start VoIP background task")
            #endif
        }
    }
    
    private func endVoIPBackgroundTask() {
        guard voipBackgroundTask != .invalid else { return }
        
        #if DEBUG
        print("MUDSocket: Ending VoIP background task")
        #endif
        UIApplication.shared.endBackgroundTask(voipBackgroundTask)
        voipBackgroundTask = .invalid
    }
    
    private func handleVoIPBackgroundTaskExpiration() {
        #if DEBUG
        print("MUDSocket: VoIP background task expiring - attempting to maintain connection")
        #endif
        
        // Send keep-alive immediately
        sendKeepAlive()
        
        // Restart VoIP background task if still enabled
        if isVoIPSocketEnabled {
            startVoIPBackgroundTask()
        }
        
        endVoIPBackgroundTask()
    }
    
    private func cleanupVoIPSocket() {
        if let source = voipSocketSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            voipSocketSource = nil
        }
        
        if let socket = voipSocket {
            CFSocketInvalidate(socket)
            voipSocket = nil
        }
    }
    
    // MARK: - Enhanced Background Connection Maintenance

    /// Start monitoring for connection loss in background
    private func startConnectionLossDetection() {
        stopConnectionLossDetection()
        
        #if DEBUG
        print("MUDSocket: Starting connection loss detection")
        #endif
        
        connectionLossDetectionTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let timeSinceLastData = Date().timeIntervalSince(self.lastDataReceiveTime)
            #if DEBUG
            print("MUDSocket: Time since last data: \(timeSinceLastData)s")
            #endif
            
            // If we haven't received data in 60 seconds, send a health check
            if timeSinceLastData > 60 {
                #if DEBUG
                print("MUDSocket: No data received for 60s, sending health check")
                #endif
                self.sendBackgroundHealthCheck()
            }
            
            // If no data for 120 seconds, consider connection lost
            if timeSinceLastData > 120 {
                #if DEBUG
                print("MUDSocket: Connection appears lost, attempting recovery")
                #endif
                self.handleBackgroundConnectionLoss()
            }
        }
    }

    private func stopConnectionLossDetection() {
        connectionLossDetectionTimer?.invalidate()
        connectionLossDetectionTimer = nil
    }

    /// Send a health check specifically designed for background operation
    private func sendBackgroundHealthCheck() {
        guard isConnected else { return }
        
        #if DEBUG
        print("MUDSocket: Sending background health check")
        #endif
        
        // Send a minimal command that should provoke a response
        let healthCheck = "look\n".data(using: .utf8)!
        
        connection?.send(content: healthCheck, completion: .contentProcessed { [weak self] error in
            if let error = error {
                #if DEBUG
                print("MUDSocket: Background health check failed: \(error)")
                #endif
                self?.consecutiveKeepAliveFailures += 1
                
                // If we've had multiple failures, attempt reconnection
                if self?.consecutiveKeepAliveFailures ?? 0 >= 3 {
                    #if DEBUG
                    print("MUDSocket: Multiple health check failures, attempting reconnection")
                    #endif
                    DispatchQueue.main.async {
                        self?.handleBackgroundConnectionLoss()
                    }
                }
            } else {
                #if DEBUG
                print("MUDSocket: Background health check succeeded")
                #endif
                self?.consecutiveKeepAliveFailures = 0
            }
        })
    }

    /// Handle connection loss detected during background operation
    private func handleBackgroundConnectionLoss() {
        #if DEBUG
        print("MUDSocket: Handling background connection loss")
        #endif
        
        // Mark as in deep background to use more aggressive reconnection
        isInDeepBackground = true
        
        // Force disconnect and attempt immediate reconnection
        connection?.cancel()
        connection = nil
        
        // Reset attempts for background recovery
        reconnectAttempts = 0
        
        // Attempt reconnection with shorter delay for background
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.attemptReconnect()
        }
    }

    /// Start background task chaining to extend background execution time
    private func startBackgroundTaskChaining() {
        stopBackgroundTaskChaining()
        
        #if DEBUG
        #if DEBUG
        print("MUDSocket: Starting background task chaining")
        #endif
        #endif
        
        // Chain background tasks every 25 seconds to maximize background time
        backgroundTaskChainTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
            #if DEBUG
            #if DEBUG
            print("MUDSocket: Background time remaining: \(backgroundTimeRemaining)s")
            #endif
            #endif
            
            if backgroundTimeRemaining < 40 {
                #if DEBUG
                #if DEBUG
                print("MUDSocket: Low background time, creating new background task")
                #endif
                #endif
                self.chainBackgroundTask()
            }
            
            // Stop chaining if we're not supposed to be in background anymore
            if !self.isInBackground {
                self.stopBackgroundTaskChaining()
            }
        }
    }

    private func stopBackgroundTaskChaining() {
        backgroundTaskChainTimer?.invalidate()
        backgroundTaskChainTimer = nil
    }

    /// Create a new background task to extend execution time
    private func chainBackgroundTask() {
        // End current task
        endConnectionMaintenanceTask()
        
        // Start a new one
        startConnectionMaintenanceTask()
        
        #if DEBUG
        print("MUDSocket: Chained background task for extended execution")
        #endif
    }
    
    // MARK: - Connection Quality Management
    
    /// Update connection quality score based on keep-alive success/failure
    private func updateConnectionQuality(success: Bool) {
        if success {
            // Improve score gradually for successful keep-alives
            connectionQualityScore = min(100, connectionQualityScore + 1)
        } else {
            // Decrease score more aggressively for failures
            connectionQualityScore = max(0, connectionQualityScore - 5)
        }
        
        #if DEBUG
        print("MUDSocket: Connection quality score: \(connectionQualityScore)")
        #endif
    }
    
    /// Get adaptive keep-alive interval based on connection quality
    private func getAdaptiveKeepAliveInterval() -> TimeInterval {
        // Adjust keep-alive frequency based on connection quality
        if connectionQualityScore >= 80 {
            return 12.0  // Good connection - less frequent
        } else if connectionQualityScore >= 50 {
            return 8.0   // Moderate connection - more frequent  
        } else {
            return 5.0   // Poor connection - very frequent
        }
    }
    
    // MARK: - Private Methods
    
    private func handleStateUpdate(_ state: NWConnection.State) {
        #if DEBUG
        print("MUDSocket: State update: \(state)")
        #endif
        
        switch state {
        case .ready:
            #if DEBUG
            print("MUDSocket: Connection is ready")
            #endif
            reconnectAttempts = 0 // Reset reconnection attempts on successful connection
            // Proactively negotiate options and advertise capabilities
            proactivelyNegotiateTelnetOptions()
            // Send MSDP XTERM_256_COLORS=1 to server
            sendXterm256Colors()
            // Send GMCP hello if enabled (server may also drive this)
            if gmcpEnabled { sendGMCPHello() }
            DispatchQueue.main.async {
                self.delegate?.mudSocket(self, didConnectToHost: self.connectedHost ?? "", port: self.connectedPort)
            }
            // Start receiving data now that connection is ready
            startReceiving()
            // Start keep-alive timer if not in background
            if !isInBackground {
                startKeepAliveTimer()
            }
            
        case .failed(let error):
            #if DEBUG
            print("MUDSocket: Connection failed with error: \(error)")
            #endif
            stopKeepAliveTimer()
            
            // Check if this might be due to socket resource reclamation
            let isResourceReclamation = isSocketResourceReclamationError(error)
            if isResourceReclamation {
                #if DEBUG
                print("MUDSocket: Detected socket resource reclamation")
                #endif
            }
            
            DispatchQueue.main.async {
                self.delegate?.mudSocket(self, didDisconnectWithError: error)
            }
            
            // Attempt reconnection if enabled
            if shouldReconnect {
                if isInBackground || isResourceReclamation {
                    // Quick reconnection attempt for resource reclamation or background
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.attemptReconnect()
                    }
                } else {
                    scheduleReconnectAttempt()
                }
            }
            
        case .cancelled:
            #if DEBUG
            print("MUDSocket: Connection was cancelled")
            #endif
            stopKeepAliveTimer()
            DispatchQueue.main.async {
                self.delegate?.mudSocket(self, didDisconnectWithError: nil)
            }
            // Don't attempt reconnection if manually cancelled
            shouldReconnect = false
            
        case .waiting(let error):
            #if DEBUG
            print("MUDSocket: Connection is waiting: \(error)")
            #endif
            
        case .preparing:
            #if DEBUG
            print("MUDSocket: Connection is preparing")
            #endif
            
        case .setup:
            #if DEBUG
            print("MUDSocket: Connection is setting up")
            #endif
            
        @unknown default:
            #if DEBUG
            print("MUDSocket: Unknown connection state: \(state)")
            #endif
        }
    }
    
    private func isSocketResourceReclamationError(_ error: Error) -> Bool {
        // Check for common errors that indicate socket resource reclamation
        let nsError = error as NSError
        
        // EBADF (Bad file descriptor) is a common sign of resource reclamation
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == EBADF {
            return true
        }
        
        // Check for NWError cases that might indicate resource issues
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let posixError):
                return posixError == .EBADF || posixError == .ENOTCONN || posixError == .EPIPE
            default:
                return false
            }
        }
        
        return false
    }
    
    private func startReceiving() {
        guard let connection = connection else { return }
        
        #if DEBUG
        print("MUDSocket: Starting to receive data...")
        #endif
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            #if DEBUG
            print("MUDSocket: Received callback - data: \(data?.count ?? 0) bytes, isComplete: \(isComplete), error: \(String(describing: error))")
            #endif
            
            if let data = data, !data.isEmpty {
                #if DEBUG
                print("MUDSocket: Received \(data.count) bytes of data")
                #endif
                
                // Update last data receive time for connection monitoring
                self?.lastDataReceiveTime = Date()
                self?.consecutiveKeepAliveFailures = 0 // Reset failure counter on successful data
                
                // Process telnet negotiation, compression, and extract plain payload
                let filtered = self?.handleTelnetNegotiation(data) ?? data
                DispatchQueue.main.async {
                    if !filtered.isEmpty {
                        // If waiting on a latency probe, compute latency on first received payload
                        if let sentAt = self?.latencyProbeSentAt, self?.awaitingLatencyProbe == true, self?.isInBackground == false {
                            let ms = Int(Date().timeIntervalSince(sentAt) * 1000)
                            self?.lastLatencyMs = ms
                            self?.awaitingLatencyProbe = false
                            self?.latencyProbeSentAt = nil
                            self?.delegate?.mudSocket(self!, didUpdateLatencyMs: ms)
                        }
                        self?.delegate?.mudSocket(self!, didReceiveData: filtered)
                    }
                }
            } else {
                #if DEBUG
                print("MUDSocket: No data received")
                #endif
            }
            
            if let error = error {
                #if DEBUG
                print("MUDSocket: Receive error: \(error)")
                #endif
                DispatchQueue.main.async {
                    self?.delegate?.mudSocket(self!, didDisconnectWithError: error)
                }
                return
            }
            
            if isComplete {
                #if DEBUG
                print("MUDSocket: Connection completed")
                #endif
                DispatchQueue.main.async {
                    self?.delegate?.mudSocket(self!, didDisconnectWithError: nil)
                }
                return
            }
            
            // Continue receiving
            self?.startReceiving()
        }
    }
    
    private func decodeDataToString(_ data: Data) -> String? {
        // Try multiple encodings commonly used by MUD servers in order of preference
        let encodings: [String.Encoding] = [
            .utf8,                     // Modern standard
            .ascii,                    // Basic ASCII
            .isoLatin1,               // ISO-8859-1 (Latin-1) - very common for MUDs
            .windowsCP1252,           // Windows-1252 - common on Windows MUD servers
            .utf16,                   // UTF-16
            .macOSRoman              // Classic Mac encoding
        ]
        
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        
        return nil
    }
    
    private func isValidHostname(_ hostname: String) -> Bool {
        // Basic hostname validation
        let hostnameRegex = "^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?([.][a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?)*$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", hostnameRegex)
        return predicate.evaluate(with: hostname) || isValidIPAddress(hostname)
    }
    
    private func isValidIPAddress(_ address: String) -> Bool {
        // Basic IP address validation
        let ipRegex = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", ipRegex)
        return predicate.evaluate(with: address)
    }
    
    private func testConnectionHealth(completion: @escaping (Bool) -> Void) {
        guard let connection = connection, connection.state == .ready else {
            completion(false)
            return
        }
        
        // Test the connection by sending a minimal keep-alive
        // If this fails, the connection has likely been reclaimed
        let testData = "\n".data(using: .utf8)!
        connection.send(content: testData, completion: .contentProcessed { error in
            DispatchQueue.main.async {
                completion(error == nil)
            }
        })
    }

    // Telnet option codes
    private let IAC: UInt8 = 255
    private let DO: UInt8 = 253
    private let WILL: UInt8 = 251
    private let DONT: UInt8 = 254
    private let WONT: UInt8 = 252
    private let SB: UInt8 = 250
    private let SE: UInt8 = 240
    // Telnet single-byte commands (IAC <cmd>) that have no option byte
    private let EOR: UInt8 = 239  // End of Record
    private let NOP: UInt8 = 241
    private let DM: UInt8 = 242   // Data Mark
    private let BRK: UInt8 = 243
    private let IP: UInt8 = 244   // Interrupt Process
    private let AO: UInt8 = 245   // Abort Output
    private let AYT: UInt8 = 246  // Are You There
    private let EC: UInt8 = 247   // Erase Character
    private let EL: UInt8 = 248   // Erase Line
    private let GA: UInt8 = 249   // Go Ahead
    private let TTYPE: UInt8 = 24
    private let SEND: UInt8 = 1
    private let IS: UInt8 = 0
    private let GMCP: UInt8 = 201
    private let MSDP: UInt8 = 69
    private let COMPRESS: UInt8 = 85
    private let COMPRESS2: UInt8 = 86

    private func handleTelnetNegotiation(_ data: Data) -> Data {
        // If MCCP is active, decompress first, then still strip any Telnet commands
        if mccpActive {
            let decompressed = decompressData(data)
            return stripTelnetCommands(from: decompressed)
        }
        var i = 0
        var filteredData = Data()
        let bytes = [UInt8](data)
        while i < bytes.count {
            let byte = bytes[i]
            if byte == IAC {
                // Ensure we have at least a verb and option
                if i + 1 < bytes.count {
                    let verb = bytes[i+1]
                    // Subnegotiation
                    if verb == SB {
                        if i + 2 < bytes.count {
                            let opt = bytes[i+2]
                            // Find end of subnegotiation: IAC SE
                            var j = i + 3
                            var foundEnd = false
                            while j + 1 < bytes.count {
                                if bytes[j] == IAC && bytes[j+1] == SE {
                                    foundEnd = true
                                    break
                                }
                                j += 1
                            }
                            let payloadRange = (i + 3)..<max(i + 3, min(j, bytes.count))
                            let payload = Data(bytes[payloadRange])
                            if opt == TTYPE {
                                // TTYPE SEND → reply with IS "xterm-256color"
                                if payload.count == 1 && payload.first == SEND {
                                    var response: [UInt8] = [IAC, SB, TTYPE, IS]
                                    response.append(contentsOf: "xterm-256color".utf8)
                                    response.append(contentsOf: [IAC, SE])
                                    print("[TTYPE] Responding to TTYPE SEND with xterm-256color")
                                    send(Data(response))
                                }
                            } else if opt == GMCP {
                                // GMCP payload is text – don't forward to output; optionally handle
                                if let text = String(data: payload, encoding: .utf8) {
                                    print("[GMCP] <- \(text)")
                                }
                            } else if opt == MSDP {
                                // MSDP payload; attempt simple parsing of VAR/VAL flat pairs
                                // Spec-compliant arrays/tables are not fully handled yet
                                let vars = self?.parseMSDP(payload: payload) ?? [:]
                                if !vars.isEmpty {
                                    print("[MSDP] Parsed: \(vars)")
                                    if let worldID = self?.currentWorldObjectID {
                                        SessionVitalsStore.shared.update(worldID: worldID, with: vars)
                                    }
                                } else {
                                    print("[MSDP] Subnegotiation received (\(payload.count) bytes)")
                                }
                            } else if opt == COMPRESS2 || opt == COMPRESS {
                                // Start MCCP(after IAC SB COMPRESS[2] IAC SE); compressed data may follow in same buffer
                                print("[MCCP] Compression negotiation complete; enabling decompression")
                                startDecompression()
                                mccpActive = true
                                // If there is data after IAC SE in this buffer, treat it as compressed
                                if foundEnd && j + 2 < bytes.count {
                                    let remaining = Data(bytes[(j+2)..<bytes.count])
                                    let decompressed = decompressData(remaining)
                                    filteredData.append(decompressed)
                                    return filteredData
                                }
                            }
                            // Skip past IAC SB ... IAC SE
                            i = foundEnd ? (j + 2) : (bytes.count)
                            continue
                        }
                    } else {
                        // DO/WILL/DONT/WONT negotiations
                        if i + 2 < bytes.count {
                            let opt = bytes[i+2]
                            if verb == DO {
                                if opt == TTYPE {
                                    // Server requests TTYPE; acknowledge
                                    send(Data([IAC, WILL, TTYPE]))
                                    print("[TTYPE] DO received → WILL sent")
                                } else if opt == GMCP {
                                    gmcpEnabled = true
                                    if NetworkingPreferences.gmcpEnabled {
                                        send(Data([IAC, WILL, GMCP]))
                                        print("[GMCP] DO received → WILL sent")
                                        // Optionally send hello immediately
                                        sendGMCPHello()
                                    } else {
                                        send(Data([IAC, WONT, GMCP]))
                                    }
                                } else if opt == MSDP {
                                    msdpEnabled = true
                                    if NetworkingPreferences.msdpEnabled {
                                        send(Data([IAC, WILL, MSDP]))
                                        print("[MSDP] DO received → WILL sent")
                                    } else {
                                        send(Data([IAC, WONT, MSDP]))
                                    }
                                } else if opt == COMPRESS2 || opt == COMPRESS {
                                    // Server requests we compress upstream (not supported) → WONT
                                    send(Data([IAC, WONT, opt]))
                                    print("[MCCP] DO received for \(opt) → WONT sent (client won't compress)")
                                } else {
                                    // Politely decline unknown DO
                                    send(Data([IAC, WONT, opt]))
                                }
                                i += 3
                                continue
                            } else if verb == WILL {
                                if opt == GMCP {
                                    // Server supports GMCP; ask it to use it
                                    if NetworkingPreferences.gmcpEnabled {
                                        send(Data([IAC, DO, GMCP]))
                                        gmcpEnabled = true
                                        print("[GMCP] WILL received → DO sent")
                                    } else {
                                        send(Data([IAC, DONT, GMCP]))
                                    }
                                } else if opt == MSDP {
                                    if NetworkingPreferences.msdpEnabled {
                                        send(Data([IAC, DO, MSDP]))
                                        msdpEnabled = true
                                        print("[MSDP] WILL received → DO sent")
                                    } else {
                                        send(Data([IAC, DONT, MSDP]))
                                    }
                                } else if opt == COMPRESS2 || opt == COMPRESS {
                                    // Server will compress; agree
                                    if NetworkingPreferences.mccpEnabled {
                                        send(Data([IAC, DO, opt]))
                                        print("[MCCP] WILL received for \(opt) → DO sent (awaiting SB to start)")
                                    } else {
                                        send(Data([IAC, DONT, opt]))
                                    }
                                } else if opt == TTYPE {
                                    // We don't need server WILL TTYPE (server shouldn't WILL TTYPE), ignore
                                } else {
                                    // Decline unknown
                                    send(Data([IAC, DONT, opt]))
                                }
                                i += 3
                                continue
                            } else if verb == DONT || verb == WONT {
                                // Acknowledge with symmetric disable
                                send(Data([IAC, verb == DONT ? WONT : DONT, opt]))
                                i += 3
                                continue
                            } else if verb == EOR || verb == NOP || verb == DM || verb == BRK || verb == IP || verb == AO || verb == AYT || verb == EC || verb == EL || verb == GA {
                                // Single-byte telnet command: drop IAC+verb
                                i += 2
                                continue
                            }
                        }
                    }
                }
                // Unknown/malformed IAC: drop IAC and the following verb if present
                i += (i + 1 < bytes.count ? 2 : 1)
                continue
            }
            // Regular data byte (uncompressed)
            filteredData.append(byte)
            i += 1
        }
        return filteredData
    }

    // Strip telnet commands from an already-decompressed payload
    private func stripTelnetCommands(from data: Data) -> Data {
        var i = 0
        var filtered = Data()
        let bytes = [UInt8](data)
        while i < bytes.count {
            let b = bytes[i]
            if b == IAC {
                if i + 1 < bytes.count {
                    let verb = bytes[i+1]
                    if verb == SB {
                        // Skip until IAC SE
                        var j = i + 2
                        var foundEnd = false
                        while j + 1 < bytes.count {
                            if bytes[j] == IAC && bytes[j+1] == SE {
                                foundEnd = true
                                break
                            }
                            j += 1
                        }
                        i = foundEnd ? (j + 2) : bytes.count
                        continue
                    } else if verb == EOR || verb == NOP || verb == DM || verb == BRK || verb == IP || verb == AO || verb == AYT || verb == EC || verb == EL || verb == GA {
                        i += 2
                        continue
                    } else if verb == DO || verb == WILL || verb == DONT || verb == WONT {
                        // Skip negotiation triplet
                        i += (i + 2 < bytes.count ? 3 : 2)
                        continue
                    } else {
                        // Unknown: drop IAC+verb
                        i += 2
                        continue
                    }
                } else {
                    // Lone IAC, drop
                    i += 1
                    continue
                }
            }
            filtered.append(b)
            i += 1
        }
        return filtered
    }

    private func proactivelyNegotiateTelnetOptions() {
        // Advertise support proactively (respect user toggles)
        if NetworkingPreferences.gmcpEnabled { send(Data([IAC, WILL, GMCP])) }
        if NetworkingPreferences.msdpEnabled { send(Data([IAC, WILL, MSDP])) }
        if NetworkingPreferences.mccpEnabled { send(Data([IAC, DO, COMPRESS2])) }
    }

    private func sendGMCP(_ payload: String) {
        var bytes: [UInt8] = [IAC, SB, GMCP]
        bytes.append(contentsOf: payload.utf8)
        bytes.append(contentsOf: [IAC, SE])
        send(Data(bytes))
        print("[GMCP] -> \(payload)")
    }

    // MARK: - MSDP naive parser (VAR/VAL flat pairs)
    // Many servers send: \x01VARname\x02VALvalue pairs inside SB MSDP ... SE
    private func parseMSDP(payload: Data) -> [String: String] {
        // MSDP tokens
        let MSDP_VAR: UInt8 = 1
        let MSDP_VAL: UInt8 = 2
        var result: [String: String] = [:]
        let bytes = [UInt8](payload)
        var i = 0
        var currentKey: String?
        while i < bytes.count {
            let b = bytes[i]
            if b == MSDP_VAR {
                // Read key until next token or end
                i += 1
                var keyBytes: [UInt8] = []
                while i < bytes.count, bytes[i] != MSDP_VAR, bytes[i] != MSDP_VAL { keyBytes.append(bytes[i]); i += 1 }
                currentKey = String(bytes: keyBytes, encoding: .utf8)
            } else if b == MSDP_VAL {
                // Read value until next token or end
                i += 1
                var valBytes: [UInt8] = []
                while i < bytes.count, bytes[i] != MSDP_VAR, bytes[i] != MSDP_VAL { valBytes.append(bytes[i]); i += 1 }
                if let key = currentKey, let value = String(bytes: valBytes, encoding: .utf8) { result[key] = value }
                currentKey = nil
            } else {
                i += 1
            }
        }
        return result
    }

    private func sendGMCPHello() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let hello = "Core.Hello {\"client\":\"MUDTapper\",\"version\":\"\(version)\"}"
        sendGMCP(hello)
    }

    // MARK: - MCCP Decompression
    private func startDecompression() {
        guard decompressionStreamInitialized == false else { return }
        // Initialize empty stream struct; fields will be set by compression_stream_init
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0), dst_size: 0, src_ptr: UnsafePointer<UInt8>(bitPattern: 0)!, src_size: 0, state: nil)
        let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        if status == COMPRESSION_STATUS_OK {
            decompressionStream = stream
            decompressionStreamInitialized = true
        } else {
            print("[MCCP] Failed to initialize decompression stream")
        }
    }

    private func endDecompression() {
        if decompressionStreamInitialized, var stream = decompressionStream {
            compression_stream_destroy(&stream)
        }
        decompressionStream = nil
        decompressionStreamInitialized = false
        mccpActive = false
    }

    private func decompressData(_ data: Data) -> Data {
        guard decompressionStreamInitialized, var stream = decompressionStream else { return Data() }
        var output = Data()
        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let srcPtr = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.src_ptr = srcPtr
            stream.src_size = data.count
            let dstBufferSize = 64 * 1024
            let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
            defer { dstBuffer.deallocate() }
            while stream.src_size > 0 {
                stream.dst_ptr = dstBuffer
                stream.dst_size = dstBufferSize
                let status = compression_stream_process(&stream, 0)
                if status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END {
                    let produced = dstBufferSize - stream.dst_size
                    if produced > 0 {
                        output.append(dstBuffer, count: produced)
                    }
                    if status == COMPRESSION_STATUS_END { break }
                } else {
                    print("[MCCP] Decompression error: \(status)")
                    break
                }
            }
        }
        // Save back the stream for continued use
        decompressionStream = stream
        return output
    }
}

// MARK: - Error Types

enum MUDSocketError: Error, LocalizedError {
    case invalidHostname
    case invalidPort
    case connectionFailed
    case disconnected
    case networkUnavailable
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .invalidHostname:
            return "Invalid hostname. Please check the server address."
        case .invalidPort:
            return "Invalid port number. Port must be between 1 and 65535."
        case .connectionFailed:
            return "Failed to connect to the server. Please check your internet connection and server details."
        case .disconnected:
            return "Connection to the server was lost."
        case .networkUnavailable:
            return "Network is unavailable. Please check your internet connection."
        case .timeout:
            return "Connection timed out. The server may be unavailable."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidHostname:
            return "Verify the server hostname or IP address is correct."
        case .invalidPort:
            return "Check with the server administrator for the correct port number."
        case .connectionFailed:
            return "Try connecting again or contact the server administrator."
        case .disconnected:
            return "Try reconnecting to the server."
        case .networkUnavailable:
            return "Check your WiFi or cellular connection and try again."
        case .timeout:
            return "Wait a moment and try connecting again."
        }
    }
} 