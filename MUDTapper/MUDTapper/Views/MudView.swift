import UIKit

protocol MudViewDelegate: AnyObject {
    func mudView(_ mudView: MudView, didRequestCreateTriggerWithPattern pattern: String)
    func mudView(_ mudView: MudView, didRequestCreateAdvancedTriggerWithPattern pattern: String)
    func mudView(_ mudView: MudView, didRequestCreateGagWithPattern pattern: String)
    func mudView(_ mudView: MudView, didRequestCustomizeRadialButtons button: Int)
    func mudView(_ mudView: MudView, didRequestResetRadialControls: Void)
}

class MudView: UIView, UIGestureRecognizerDelegate, UITextViewDelegate {
    
    // MARK: - Properties
    
    weak var delegate: MudViewDelegate?
    
    private var textView: UITextView!
    private var attributedText: NSMutableAttributedString = NSMutableAttributedString()
    
    // Smooth append/scroll management
    private var pendingFragments: [NSAttributedString] = []
    private var appendTimer: Timer?
    private let minFlushInterval: TimeInterval = 0.02
    private let maxFlushInterval: TimeInterval = 0.12
    private var isAppInBackground: Bool = false
    private var autoScrollEnabled: Bool = true
    private var userPausedAutoScroll: Bool = false
    private var unreadCount: Int = 0
    private var jumpToLatestButton: UIButton?
    private var longPressGesture: UILongPressGestureRecognizer!
    private var selectedLineText: String?
    private let themeManager: ThemeManager
    private var ansiProcessor: ANSIProcessor
    
    // Radial button system - Two directional pads
    private var leftRadialButton: RadialDirectionalPad!
    private var rightRadialButton: RadialDirectionalPad!
    
    // MARK: - Initialization
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        self.ansiProcessor = ANSIProcessor(themeManager: themeManager)
        super.init(frame: .zero)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported for MudView; use init(themeManager:)")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        backgroundColor = themeManager.terminalBackgroundColor
        
        // Create text view
        textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = themeManager.terminalFont
        textView.textColor = themeManager.terminalTextColor
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.showsVerticalScrollIndicator = true
        textView.alwaysBounceVertical = true
        textView.delegate = self
        
        // Ensure proper scrolling behavior
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.maximumNumberOfLines = 0
        
        // Accessibility
        textView.isAccessibilityElement = true
        textView.accessibilityLabel = "MUD Terminal Output"
        textView.accessibilityHint = "Displays text from the MUD server. Long press on a line to create triggers or gags."
        textView.accessibilityTraits = [.staticText, .updatesFrequently]
        
        addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Add long press gesture recognizer
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.delegate = self
        longPressGesture.cancelsTouchesInView = false
        textView.addGestureRecognizer(longPressGesture)
        
        // Add some welcome text
        appendTextWithColor("Welcome to MUDTapper!\n", color: themeManager.linkColor)
        appendTextWithColor("Connect to a MUD world to begin your adventure.\n\n", color: themeManager.terminalTextColor.withAlphaComponent(0.7))
        
        // Setup radial directional pads
        setupRadialDirectionalPads()

        // Jump to latest control (appears when user scrolls up)
        setupJumpToLatestButton()
        
        // Configure accessibility for the container
        isAccessibilityElement = false
        accessibilityElements = [textView, leftRadialButton, rightRadialButton].compactMap { $0 }

        // Observe app state for dynamic UI cadence
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppStateChange(_:)), name: .appDidEnterBackground, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppStateChange(_:)), name: .appDidBecomeActive, object: nil)
    }
    
    private func setupRadialDirectionalPads() {
        // Left radial button (bottom-left)
        leftRadialButton = RadialDirectionalPad(buttonIndex: 0, themeManager: themeManager)
        leftRadialButton.translatesAutoresizingMaskIntoConstraints = false
        leftRadialButton.delegate = self
        addSubview(leftRadialButton)
        
        // Right radial button (bottom-right)
        rightRadialButton = RadialDirectionalPad(buttonIndex: 1, themeManager: themeManager)
        rightRadialButton.translatesAutoresizingMaskIntoConstraints = false
        rightRadialButton.delegate = self
        addSubview(rightRadialButton)
        
        // Position the radial buttons responsively
        updateRadialButtonConstraints()
    }

    private func setupJumpToLatestButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = "Jump to Latest"
        config.baseForegroundColor = themeManager.linkColor
        config.baseBackgroundColor = themeManager.linkColor.withAlphaComponent(0.15)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attrs = incoming
            attrs.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            return attrs
        }
        button.configuration = config
        button.alpha = 0.0
        button.addTarget(self, action: #selector(jumpToLatestTapped), for: .touchUpInside)
        addSubview(button)
        bringSubviewToFront(button)
        
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        self.jumpToLatestButton = button
    }

    @objc private func jumpToLatestTapped() {
        scrollToBottom()
    }

    private func updateJumpToLatestVisibility() {
        let shouldShow = !autoScrollEnabled && unreadCount > 0
        let targetAlpha: CGFloat = shouldShow ? 1.0 : 0.0
        guard jumpToLatestButton?.alpha != targetAlpha else { return }
        UIView.animate(withDuration: 0.2) {
            self.jumpToLatestButton?.alpha = targetAlpha
        }
    }
    
    private func updateRadialButtonConstraints() {
        // Remove existing constraints
        leftRadialButton.removeFromSuperview()
        rightRadialButton.removeFromSuperview()
        addSubview(leftRadialButton)
        addSubview(rightRadialButton)
        
        // Get user preferences for radial control positions
        let leftPosition = RadialControl.radialControlPosition()
        let rightPosition = RadialControl.moveControlPosition()
        
        // Calculate responsive size based on screen size
        let screenSize = UIScreen.main.bounds.size
        let minDimension = min(screenSize.width, screenSize.height)
        let buttonSize: CGFloat = max(80, min(120, minDimension * 0.15)) // 15% of smaller screen dimension, clamped between 80-120
        let margin: CGFloat = max(34, minDimension * 0.048) // 4.8% of smaller screen dimension, minimum 34
        
        var leftConstraints: [NSLayoutConstraint] = []
        var rightConstraints: [NSLayoutConstraint] = []
        
        // Configure left radial button based on user preference
        switch leftPosition {
        case .left:
            leftConstraints = [
                leftRadialButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),
                leftRadialButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
                leftRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                leftRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
            ]
            leftRadialButton.isHidden = false
        case .right:
            leftConstraints = [
                leftRadialButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
                leftRadialButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
                leftRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                leftRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
            ]
            leftRadialButton.isHidden = false
        case .hidden:
            leftRadialButton.isHidden = true
        }
        
        // Configure right radial button based on user preference
        switch rightPosition {
        case .left:
            rightConstraints = [
                rightRadialButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),
                rightRadialButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
                rightRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                rightRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
            ]
            rightRadialButton.isHidden = false
        case .right:
            rightConstraints = [
                rightRadialButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
                rightRadialButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
                rightRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                rightRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
            ]
            rightRadialButton.isHidden = false
        case .hidden:
            rightRadialButton.isHidden = true
        }
        
        // Handle case where both buttons are in the same position
        if leftPosition == rightPosition && leftPosition != .hidden {
            // Stack them vertically with some spacing
            let spacing: CGFloat = 8
            if leftPosition == .left {
                // Both on left side, stack vertically
                leftConstraints = [
                    leftRadialButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),
                    leftRadialButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
                    leftRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                    leftRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
                ]
                rightConstraints = [
                    rightRadialButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),
                    rightRadialButton.bottomAnchor.constraint(equalTo: leftRadialButton.topAnchor, constant: -spacing),
                    rightRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                    rightRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
                ]
            } else {
                // Both on right side, stack vertically
                leftConstraints = [
                    leftRadialButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
                    leftRadialButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
                    leftRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                    leftRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
                ]
                rightConstraints = [
                    rightRadialButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
                    rightRadialButton.bottomAnchor.constraint(equalTo: leftRadialButton.topAnchor, constant: -spacing),
                    rightRadialButton.widthAnchor.constraint(equalToConstant: buttonSize),
                    rightRadialButton.heightAnchor.constraint(equalToConstant: buttonSize)
                ]
            }
        }
        
        NSLayoutConstraint.activate(leftConstraints + rightConstraints)
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        // Update radial button layout when device orientation changes
        if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass ||
           traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass {
            updateRadialButtonConstraints()
        }
    }
    
    // Public method to update radial button constraints
    func updateRadialButtonLayout() {
        updateRadialButtonConstraints()
    }
    
    // MARK: - Long Press Handling (for line selection)
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let point = gesture.location(in: textView)
            
            // Ensure we have text to work with
            guard !textView.text.isEmpty else {
                return
            }
            
            // Find the line at the touch point using a more accurate method
            let selectedLine = findLineAtPoint(point)
            
            // Skip empty lines
            guard !selectedLine.isEmpty else {
                return
            }
            
            selectedLineText = selectedLine
            showLineSelectionMenu(at: point)
        }
    }
    
    private func findLineAtPoint(_ point: CGPoint) -> String {
        // Adjust point for text container insets
        let adjustedPoint = CGPoint(
            x: point.x - textView.textContainerInset.left,
            y: point.y - textView.textContainerInset.top
        )
        
        // Use the layout manager to find the exact line fragment at the touch point
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let textStorage = textView.textStorage
        
        // Get the character index closest to the touch point
        let characterIndex = layoutManager.characterIndex(
            for: adjustedPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        
        // Ensure character index is within bounds
        guard characterIndex < textStorage.length else {
            return ""
        }
        
        // Find the line fragment rectangle that contains this character
        var lineRange = NSRange()
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: characterIndex, effectiveRange: &lineRange)
        
        // Check if the touch point is actually within the line fragment
        let expandedLineRect = lineRect.insetBy(dx: -10, dy: -5) // Add some tolerance
        guard expandedLineRect.contains(adjustedPoint) else {
            return ""
        }
        
        // Get the actual text for this line range
        let lineText = textStorage.attributedSubstring(from: lineRange).string
        let trimmedLineText = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty lines
        guard !trimmedLineText.isEmpty else {
            return ""
        }
        
        return trimmedLineText
    }
    
    private func showLineSelectionMenu(at point: CGPoint) {
        guard let lineText = selectedLineText else { return }
        
        let alert = UIAlertController(title: "Selected Line", message: lineText, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Copy", style: .default) { _ in
            UIPasteboard.general.string = lineText
        })
        
        alert.addAction(UIAlertAction(title: "⚡ Quick Trigger", style: .default) { _ in
            self.delegate?.mudView(self, didRequestCreateTriggerWithPattern: lineText)
        })
        
        alert.addAction(UIAlertAction(title: "🔧 Advanced Trigger", style: .default) { _ in
            self.delegate?.mudView(self, didRequestCreateAdvancedTriggerWithPattern: lineText)
        })
        
        alert.addAction(UIAlertAction(title: "Create Gag", style: .default) { _ in
            self.delegate?.mudView(self, didRequestCreateGagWithPattern: lineText)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // Find the view controller to present from
        var responder: UIResponder? = self
        while responder != nil {
            if let viewController = responder as? UIViewController {
                // For iPad, set up popover
                if let popover = alert.popoverPresentationController {
                    popover.sourceView = self
                    popover.sourceRect = CGRect(origin: point, size: CGSize(width: 1, height: 1))
                }
                
                viewController.present(alert, animated: true)
                break
            }
            responder = responder?.next
        }
    }
    
    // MARK: - Text Management
    
    func appendText(_ text: String, color: UIColor = UIColor.label) {
        // Use ANSI processor for consistent color handling
        let processedText = ansiProcessor.processText(text)
        appendAttributedText(processedText)
    }
    
    func appendTextWithColor(_ text: String, color: UIColor) {
        let attributedText = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: themeManager.terminalFont
        ])
        appendAttributedText(attributedText)
    }
    
    func appendAttributedText(_ text: NSAttributedString) {
        // Enqueue fragments and flush on a short cadence to avoid choppy UI
        let enqueue: () -> Void = {
            self.pendingFragments.append(text)
            self.scheduleAppendFlush()
        }
        if Thread.isMainThread { enqueue() } else { DispatchQueue.main.async { enqueue() } }
    }
    
    // MARK: - ANSI Color Testing
    
    func testANSIColors() {
        let testText = """
        
=== ANSI Color Test ===

Standard ANSI Colors:
\u{1B}[30mBlack\u{1B}[0m \u{1B}[31mRed\u{1B}[0m \u{1B}[32mGreen\u{1B}[0m \u{1B}[33mYellow\u{1B}[0m \u{1B}[34mBlue\u{1B}[0m \u{1B}[35mMagenta\u{1B}[0m \u{1B}[36mCyan\u{1B}[0m \u{1B}[37mWhite\u{1B}[0m

Bright ANSI Colors:
\u{1B}[90mBright Black\u{1B}[0m \u{1B}[91mBright Red\u{1B}[0m \u{1B}[92mBright Green\u{1B}[0m \u{1B}[93mBright Yellow\u{1B}[0m \u{1B}[94mBright Blue\u{1B}[0m \u{1B}[95mBright Magenta\u{1B}[0m \u{1B}[96mBright Cyan\u{1B}[0m \u{1B}[97mBright White\u{1B}[0m

Background Colors:
\u{1B}[40mBlack BG\u{1B}[0m \u{1B}[41mRed BG\u{1B}[0m \u{1B}[42mGreen BG\u{1B}[0m \u{1B}[43mYellow BG\u{1B}[0m \u{1B}[44mBlue BG\u{1B}[0m \u{1B}[45mMagenta BG\u{1B}[0m \u{1B}[46mCyan BG\u{1B}[0m \u{1B}[47mWhite BG\u{1B}[0m

XTERM 256-Color Test:
\u{1B}[38;5;196mBright Red (196)\u{1B}[0m \u{1B}[38;5;46mBright Green (46)\u{1B}[0m \u{1B}[38;5;21mBright Blue (21)\u{1B}[0m
\u{1B}[38;5;226mBright Yellow (226)\u{1B}[0m \u{1B}[38;5;201mBright Magenta (201)\u{1B}[0m \u{1B}[38;5;51mBright Cyan (51)\u{1B}[0m

Color Cube Test:
\u{1B}[38;5;16mColor 16\u{1B}[0m \u{1B}[38;5;52mColor 52\u{1B}[0m \u{1B}[38;5;88mColor 88\u{1B}[0m \u{1B}[38;5;124mColor 124\u{1B}[0m \u{1B}[38;5;160mColor 160\u{1B}[0m \u{1B}[38;5;196mColor 196\u{1B}[0m

Grayscale Test:
\u{1B}[38;5;232mGray 232\u{1B}[0m \u{1B}[38;5;240mGray 240\u{1B}[0m \u{1B}[38;5;248mGray 248\u{1B}[0m \u{1B}[38;5;255mGray 255\u{1B}[0m

RGB Color Test:
\u{1B}[38;2;255;0;0mRGB Red\u{1B}[0m \u{1B}[38;2;0;255;0mRGB Green\u{1B}[0m \u{1B}[38;2;0;0;255mRGB Blue\u{1B}[0m
\u{1B}[38;2;255;255;0mRGB Yellow\u{1B}[0m \u{1B}[38;2;255;0;255mRGB Magenta\u{1B}[0m \u{1B}[38;2;0;255;255mRGB Cyan\u{1B}[0m

Background Color Tests:
\u{1B}[48;5;196mBright Red BG\u{1B}[0m \u{1B}[48;5;46mBright Green BG\u{1B}[0m \u{1B}[48;5;21mBright Blue BG\u{1B}[0m
\u{1B}[48;2;255;0;0mRGB Red BG\u{1B}[0m \u{1B}[48;2;0;255;0mRGB Green BG\u{1B}[0m \u{1B}[48;2;0;0;255mRGB Blue BG\u{1B}[0m

Combined Foreground/Background:
\u{1B}[38;5;196;48;5;16mRed on Black\u{1B}[0m \u{1B}[38;5;16;48;5;196mBlack on Red\u{1B}[0m
\u{1B}[38;5;46;48;5;16mGreen on Black\u{1B}[0m \u{1B}[38;5;16;48;5;46mBlack on Green\u{1B}[0m

Text Formatting:
\u{1B}[1mBold\u{1B}[0m \u{1B}[3mItalic\u{1B}[0m \u{1B}[4mUnderlined\u{1B}[0m \u{1B}[9mStrikethrough\u{1B}[0m
\u{1B}[1;31mBold Red\u{1B}[0m \u{1B}[1;32mBold Green\u{1B}[0m \u{1B}[1;34mBold Blue\u{1B}[0m

tbaMUD Color Test:
@rRed@gGreen@bBlue@yYellow@mMagenta@cCyan@wWhite@n
@R@rBold Red@G@gBold Green@B@bBold Blue@Y@yBold Yellow@M@mBold Magenta@C@cBold Cyan@W@wBold White@n

tbaMUD 256-Color Test:
@[F196]tbaMUD Red@[F046]tbaMUD Green@[F021]tbaMUD Blue@n
@[B196]tbaMUD Red BG@[B046]tbaMUD Green BG@[B021]tbaMUD Blue BG@n

=== End ANSI Color Test ===

"""
        
        appendText(testText)
    }
    
    func testXterm256ColorPalette() {
        // Test xterm256 color palette - removed debug method
        appendText("Xterm256 color palette test removed for production\n")
    }
    
    func scrollToBottom() {
        userPausedAutoScroll = false
        autoScrollEnabled = true
        unreadCount = 0
        updateJumpToLatestVisibility()
        efficientScrollToBottom(force: true)
    }
    
    private func efficientScrollToBottom(force: Bool = false) {
        // Ensure we're on the main queue
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.efficientScrollToBottom(force: force)
            }
            return
        }
        
        // Quick performance check - only scroll if we have content
        guard attributedText.length > 0, textView.contentSize.height > 0 else { return }
        
        // Only auto-scroll if enabled or forced
        guard force || autoScrollEnabled || isNearBottom() else { return }
        
        // Use the most efficient scrolling method
        let textLength = attributedText.length
        if textLength > 0 {
            let endRange = NSRange(location: textLength - 1, length: 1)
            textView.scrollRangeToVisible(endRange)
        }
    }

    private func isNearBottom(threshold: CGFloat = 60) -> Bool {
        let contentHeight = textView.contentSize.height
        let visibleHeight = textView.bounds.height - textView.contentInset.top - textView.contentInset.bottom
        let offsetY = textView.contentOffset.y
        return (contentHeight - (offsetY + visibleHeight)) < threshold
    }

    // Timer-based batching to smooth UI updates when many small fragments arrive
    private func scheduleAppendFlush() {
        appendTimer?.invalidate()
        
        // Dynamically adapt cadence based on backlog, user intent, and app state
        let backlog = pendingFragments.count
        var interval = minFlushInterval
        
        if userPausedAutoScroll {
            // When user is reading older text, slow down updates a bit
            interval = max(interval, 0.06)
        }
        
        if backlog > 100 {
            interval = max(interval, 0.10)
        } else if backlog > 30 {
            interval = max(interval, 0.06)
        } else if backlog > 10 {
            interval = max(interval, 0.04)
        }
        
        if isAppInBackground {
            // In background, UI rendering is not visible; reduce churn
            interval = max(interval, 0.12)
        }
        
        let clamped = min(maxFlushInterval, max(minFlushInterval, interval))
        appendTimer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: false) { [weak self] _ in
            self?.flushPendingFragments()
        }
    }

    private func flushPendingFragments() {
        guard !pendingFragments.isEmpty else { return }
        let fragments = pendingFragments
        pendingFragments.removeAll()
        
        // Append all at once for smoother updates
        let batch = NSMutableAttributedString()
        fragments.forEach { batch.append($0) }
        
        // Respect user intent: only pause when user has scrolled up
        autoScrollEnabled = !userPausedAutoScroll
        if userPausedAutoScroll { unreadCount += 1 }
        updateJumpToLatestVisibility()
        
        // Apply with buffer limit to backing store
        attributedText.append(batch)
        let maxTextLength = 50000
        var excessLength = 0
        if attributedText.length > maxTextLength {
            excessLength = attributedText.length - maxTextLength
            attributedText.deleteCharacters(in: NSRange(location: 0, length: excessLength))
        }
        
        // Update the text view incrementally to avoid full re-layouts
        textView.textStorage.beginEditing()
        textView.textStorage.append(batch)
        if excessLength > 0 {
            // Trim from the start in the visible storage as well
            textView.textStorage.deleteCharacters(in: NSRange(location: 0, length: excessLength))
        }
        textView.textStorage.endEditing()
        
        // Scroll if appropriate
        efficientScrollToBottom()
    }

    @objc private func handleAppStateChange(_ notification: Notification) {
        if notification.name == .appDidEnterBackground {
            isAppInBackground = true
        } else if notification.name == .appDidBecomeActive {
            isAppInBackground = false
        }
    }
    
    func clearText() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.textView.text = ""
            self.attributedText = NSMutableAttributedString()
        }
    }
    
    func applyTheme() {
        backgroundColor = themeManager.terminalBackgroundColor
        textView?.backgroundColor = UIColor.clear
        
        // Don't set textView.textColor as it overrides existing attributed text colors
        // Instead, only set it if we have no existing attributed text
        if attributedText.length == 0 {
            textView?.textColor = themeManager.terminalTextColor
        }
        
        textView?.font = themeManager.terminalFont
        
        // Refresh ANSI processor colors to ensure consistency
        ansiProcessor.refreshThemeColors()
        
        // Update radial button themes
        leftRadialButton?.applyTheme()
        rightRadialButton?.applyTheme()

        // Update jump button theme
        if let button = jumpToLatestButton {
            button.backgroundColor = themeManager.linkColor.withAlphaComponent(0.15)
            button.tintColor = themeManager.linkColor
        }
    }
    
    // Public method to reset all radial controls if they get stuck
    func resetAllRadialControls() {
        leftRadialButton?.forceReset()
        rightRadialButton?.forceReset()
    }
    
    // Delegate method to request reset from parent
    func requestResetRadialControls() {
        delegate?.mudView(self, didRequestResetRadialControls: ())
    }
    
    // MARK: - UITextViewDelegate
    
    func textViewDidChange(_ textView: UITextView) {
        // Only follow if user hasn't scrolled up
        efficientScrollToBottom()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Only treat it as user-paused if the user is dragging (not when content grows quickly)
        if scrollView.isDragging {
            let nowNearBottom = isNearBottom()
            userPausedAutoScroll = !nowNearBottom
            autoScrollEnabled = !userPausedAutoScroll
            updateJumpToLatestVisibility()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MudView {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow long press to work with other gestures
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle touches on the text view
        return touch.view == textView || touch.view?.isDescendant(of: textView) == true
    }
}

// MARK: - RadialDirectionalPadDelegate

extension MudView: RadialDirectionalPadDelegate {
    func radialPad(_ pad: RadialDirectionalPad, didTriggerDirection direction: RadialDirection) {
        let command = getCommandForDirection(direction, buttonIndex: pad.buttonIndex)
        if !command.isEmpty {
            sendCommand(command)
        }
    }
    
    func radialPad(_ pad: RadialDirectionalPad, didRequestCustomization buttonIndex: Int) {
        delegate?.mudView(self, didRequestCustomizeRadialButtons: buttonIndex)
    }
    
    private func getCommandForDirection(_ direction: RadialDirection, buttonIndex: Int) -> String {
        let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
        return UserDefaults.standard.string(forKey: key) ?? direction.defaultCommand
    }
    
    private func sendCommand(_ command: String) {
        // Send command immediately without notification overhead for better responsiveness
        if let parentController = findParentController() as? ClientViewController {
            parentController.processCommand(command)
        } else {
            // Fallback to notification if we can't find the controller directly
            NotificationCenter.default.post(
                name: .radialButtonCommand,
                object: command
            )
        }
    }
    
    private func findParentController() -> UIViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            if let viewController = responder as? UIViewController {
                return viewController
            }
            responder = responder?.next
        }
        return nil
    }
}

// MARK: - RadialDirectionalPad

protocol RadialDirectionalPadDelegate: AnyObject {
    func radialPad(_ pad: RadialDirectionalPad, didTriggerDirection direction: RadialDirection)
    func radialPad(_ pad: RadialDirectionalPad, didRequestCustomization buttonIndex: Int)
}

class RadialDirectionalPad: UIView {
    
    weak var delegate: RadialDirectionalPadDelegate?
    let buttonIndex: Int
    private let themeManager: ThemeManager
    
    private var panGesture: UIPanGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var centerPoint: CGPoint = .zero
    private var currentDirection: RadialDirection?
    private var isActive = false
    
    // Visual elements
    private var backgroundCircle: CAShapeLayer!
    private var directionIndicator: CAShapeLayer!
    private var directionLabels: [CATextLayer] = []
    private var activeDirectionLabel: CATextLayer!
    
    private var style: RadialControlStyle {
        return RadialControl.radialControlStyle()
    }
    
    private var labelsVisible: Bool {
        return RadialControl.radialControlLabelsVisible()
    }
    
    init(buttonIndex: Int, themeManager: ThemeManager) {
        self.buttonIndex = buttonIndex
        self.themeManager = themeManager
        super.init(frame: .zero)
        setupUI()
        setupGestures()
        NotificationCenter.default.addObserver(self, selector: #selector(updateStyle), name: Notification.Name("RadialControlStyleChanged"), object: nil)
    }
    
    override init(frame: CGRect) {
        self.buttonIndex = 0
        self.themeManager = ThemeManager.shared // Fallback to shared if not initialized here
        super.init(frame: frame)
        setupUI()
        setupGestures()
        NotificationCenter.default.addObserver(self, selector: #selector(updateStyle), name: Notification.Name("RadialControlStyleChanged"), object: nil)
    }
    
    required init?(coder: NSCoder) {
        self.buttonIndex = 0
        self.themeManager = ThemeManager.shared // Fallback to shared if not initialized here
        super.init(coder: coder)
        setupUI()
        setupGestures()
        NotificationCenter.default.addObserver(self, selector: #selector(updateStyle), name: Notification.Name("RadialControlStyleChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        stopResetTimer()
    }
    
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            // View is being removed, reset control
            forceReset()
        }
    }
    
    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview == nil {
            // View is being removed, reset control
            forceReset()
        }
    }
    
    private func setupUI() {
        // Background circle
        backgroundCircle = CAShapeLayer()
        layer.addSublayer(backgroundCircle)
        
        // Direction indicator
        directionIndicator = CAShapeLayer()
        layer.addSublayer(directionIndicator)
        
        // Active direction label (appears when direction is activated)
        activeDirectionLabel = CATextLayer()
        activeDirectionLabel.fontSize = 16
        activeDirectionLabel.alignmentMode = .center
        activeDirectionLabel.contentsScale = UIScreen.main.scale
        activeDirectionLabel.isHidden = true
        layer.addSublayer(activeDirectionLabel)
        
        // Direction labels
        setupDirectionLabels()
        
        applyTheme()
    }
    
    private func setupDirectionLabels() {
        for direction in RadialDirection.allCases {
            let label = CATextLayer()
            label.string = direction.rawValue
            label.fontSize = 12
            label.alignmentMode = .center
            label.contentsScale = UIScreen.main.scale
            layer.addSublayer(label)
            directionLabels.append(label)
        }
    }
    
    private func setupGestures() {
        // Pan gesture for direction detection
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
        
        // Long press for customization
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 1.0
        addGestureRecognizer(longPressGesture)
    }
    
    @objc private func updateStyle() {
        applyTheme()
        setNeedsLayout()
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            isActive = true
            showDirectionIndicator(true)
            stopResetTimer()
            // Always update direction on begin, even if in center
            updateDirection(for: location)
        case .changed:
            // Always update direction, regardless of bounds or center position
            updateDirection(for: location)
            stopResetTimer()
        case .ended, .cancelled, .failed:
            if let direction = currentDirection {
                delegate?.radialPad(self, didTriggerDirection: direction)
            }
            resetControl()
            stopResetTimer()
        default:
            resetControl()
            stopResetTimer()
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            delegate?.radialPad(self, didRequestCustomization: buttonIndex)
        }
    }
    
    private func showDirectionIndicator(_ show: Bool) {
        directionIndicator.isHidden = !show
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        for label in directionLabels {
            label.opacity = show ? 1.0 : 0.7
        }
        CATransaction.commit()
    }
    
    private func updateDirection(for location: CGPoint) {
        let dx = location.x - centerPoint.x
        let dy = location.y - centerPoint.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // Allow direction detection even from the center (no dead zone)
        // Only reset if the finger is very close to center (within 5 points)
        guard distance > 5 else {
            currentDirection = nil
            updateDirectionIndicator()
            return
        }
        
        var angle = atan2(dy, dx) * 180 / .pi + 90
        if angle < 0 { angle += 360 }
        let newDirection: RadialDirection
        switch angle {
        case 337.5...360, 0..<22.5:
            newDirection = .north
        case 22.5..<67.5:
            newDirection = .northeast
        case 67.5..<112.5:
            newDirection = .east
        case 112.5..<157.5:
            newDirection = .southeast
        case 157.5..<202.5:
            newDirection = .south
        case 202.5..<247.5:
            newDirection = .southwest
        case 247.5..<292.5:
            newDirection = .west
        case 292.5..<337.5:
            newDirection = .northwest
        default:
            newDirection = .north
        }
        if newDirection != currentDirection {
            currentDirection = newDirection
            updateDirectionIndicator()
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
    }
    
    private func updateDirectionIndicator() {
        guard let direction = currentDirection else {
            directionIndicator.path = nil
            activeDirectionLabel.isHidden = true
            return
        }
        
        let radius = min(bounds.width, bounds.height) / 2 - 10
        let angle = direction.angle * .pi / 180 - .pi/2
        let indicatorRadius: CGFloat = 15
        let x = centerPoint.x + cos(angle) * (radius * 0.7)
        let y = centerPoint.y + sin(angle) * (radius * 0.7)
        
        // Update direction indicator
        let indicatorPath = UIBezierPath(arcCenter: CGPoint(x: x, y: y), radius: indicatorRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        directionIndicator.path = indicatorPath.cgPath
        
        // Update active direction label
        activeDirectionLabel.string = direction.rawValue
        activeDirectionLabel.frame = CGRect(x: x - 20, y: y - 12, width: 40, height: 24)
        activeDirectionLabel.isHidden = false
        activeDirectionLabel.opacity = 0.8
        activeDirectionLabel.foregroundColor = themeManager.linkColor.cgColor
    }
    
    private func resetControl() {
        isActive = false
        currentDirection = nil
        showDirectionIndicator(false)
        activeDirectionLabel.isHidden = true
    }
    
    // Add a safety timer to reset the control if it gets stuck
    private var resetTimer: Timer?
    
    private func startResetTimer() {
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.resetControl()
        }
    }
    
    private func stopResetTimer() {
        resetTimer?.invalidate()
        resetTimer = nil
    }
    
    // Add a public method to force reset the control (can be called from outside if needed)
    func forceReset() {
        resetControl()
        stopResetTimer()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius = min(bounds.width, bounds.height) / 2 - 10
        var radius = baseRadius
        var labelAlpha: Float = 0.7
        var labelHidden = false
        var bgAlpha: CGFloat = 0.4
        var strokeAlpha: CGFloat = 0.6
        let bgColor: UIColor = themeManager.terminalBackgroundColor
        let strokeColor: UIColor = themeManager.linkColor
        var showFill = true
        var showStroke = true
        var hidePad = false
        var labelFontSize: CGFloat = 12
        
        switch style {
        case .standard:
            // Default values
            break
        case .minimal:
            radius *= 0.6
            labelAlpha = 0.5
            bgAlpha = 0.2
            strokeAlpha = 0.3
            labelFontSize = 10
        case .transparent:
            bgAlpha = 0.05
            strokeAlpha = 0.1
            labelAlpha = isActive ? 1.0 : 0.2
            labelFontSize = 10
        case .outline:
            showFill = false
            showStroke = true
            bgAlpha = 0.0
            strokeAlpha = 0.7
            labelAlpha = 0.7
        case .hidden:
            hidePad = !isActive
            labelHidden = !isActive
        }
        
        backgroundCircle.isHidden = hidePad
        directionIndicator.isHidden = hidePad
        for label in directionLabels { 
            label.isHidden = labelHidden || !labelsVisible 
        }
        
        // Update background circle
        let circlePath = UIBezierPath(arcCenter: centerPoint, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        backgroundCircle.path = circlePath.cgPath
        backgroundCircle.fillColor = showFill ? bgColor.withAlphaComponent(bgAlpha).cgColor : UIColor.clear.cgColor
        backgroundCircle.strokeColor = showStroke ? strokeColor.withAlphaComponent(strokeAlpha).cgColor : UIColor.clear.cgColor
        backgroundCircle.lineWidth = 2
        
        // Update direction labels
        for (index, direction) in RadialDirection.allCases.enumerated() {
            let label = directionLabels[index]
            let angle = direction.angle * .pi / 180
            let labelRadius = radius * 0.8
            let x = centerPoint.x + cos(angle - .pi/2) * labelRadius
            let y = centerPoint.y + sin(angle - .pi/2) * labelRadius
            label.frame = CGRect(x: x - 15, y: y - 8, width: 30, height: 16)
            label.opacity = labelAlpha
            label.fontSize = labelFontSize
            label.foregroundColor = themeManager.terminalTextColor.cgColor
        }
    }
    
    func applyTheme() {
        let style = self.style
        switch style {
        case .standard:
            backgroundCircle?.fillColor = themeManager.terminalBackgroundColor.withAlphaComponent(0.4).cgColor
            backgroundCircle?.strokeColor = themeManager.linkColor.withAlphaComponent(0.6).cgColor
            directionIndicator?.fillColor = themeManager.linkColor.withAlphaComponent(0.8).cgColor
        case .minimal:
            backgroundCircle?.fillColor = themeManager.terminalBackgroundColor.withAlphaComponent(0.2).cgColor
            backgroundCircle?.strokeColor = themeManager.linkColor.withAlphaComponent(0.3).cgColor
            directionIndicator?.fillColor = themeManager.linkColor.withAlphaComponent(0.5).cgColor
        case .transparent:
            backgroundCircle?.fillColor = themeManager.terminalBackgroundColor.withAlphaComponent(0.05).cgColor
            backgroundCircle?.strokeColor = themeManager.linkColor.withAlphaComponent(0.1).cgColor
            directionIndicator?.fillColor = themeManager.linkColor.withAlphaComponent(0.2).cgColor
        case .outline:
            backgroundCircle?.fillColor = UIColor.clear.cgColor
            backgroundCircle?.strokeColor = themeManager.linkColor.withAlphaComponent(0.7).cgColor
            directionIndicator?.fillColor = themeManager.linkColor.withAlphaComponent(0.8).cgColor
        case .hidden:
            backgroundCircle?.fillColor = UIColor.clear.cgColor
            backgroundCircle?.strokeColor = UIColor.clear.cgColor
            directionIndicator?.fillColor = UIColor.clear.cgColor
        }
        for label in directionLabels {
            label.foregroundColor = themeManager.terminalTextColor.cgColor
        }
        activeDirectionLabel.foregroundColor = themeManager.linkColor.cgColor
        setNeedsLayout()
    }
}

// MARK: - UIView Extension

extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let radialButtonCommand = Notification.Name("RadialButtonCommand")
} 