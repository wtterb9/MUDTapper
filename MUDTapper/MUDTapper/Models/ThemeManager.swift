import UIKit
import Foundation

// MARK: - Custom Theme Model

struct CustomTheme {
    var name: String = ""
    var terminalBackground: UIColor = .black
    var interfaceBackground: UIColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
    var foregroundColor: UIColor = .white
    var linkColor: UIColor = .systemBlue
    var inputTextColor: UIColor = .white
    var ansiRed: UIColor = .systemRed
    var ansiGreen: UIColor = .systemGreen
    var ansiYellow: UIColor = .systemYellow
    var ansiBlue: UIColor = .systemBlue
    var ansiMagenta: UIColor = .systemPurple
    var ansiCyan: UIColor = .systemTeal
    var ansiWhite: UIColor = .white
    
    func toThemeData() -> [String: Any] {
        return [
            "name": name,
            "terminalBackground": terminalBackground.toHex(),
            "interfaceBackground": interfaceBackground.toHex(),
            "foregroundColor": foregroundColor.toHex(),
            "linkColor": linkColor.toHex(),
            "inputTextColor": inputTextColor.toHex(),
            "ansiRed": ansiRed.toHex(),
            "ansiGreen": ansiGreen.toHex(),
            "ansiYellow": ansiYellow.toHex(),
            "ansiBlue": ansiBlue.toHex(),
            "ansiMagenta": ansiMagenta.toHex(),
            "ansiCyan": ansiCyan.toHex(),
            "ansiWhite": ansiWhite.toHex()
        ]
    }
}

// MARK: - UIColor Extension

extension UIColor {
    var isDarkColor: Bool {
        var white: CGFloat = 0
        getWhite(&white, alpha: nil)
        return white < 0.5
    }
    
    func toHex() -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let rgb = Int(red * 255) << 16 | Int(green * 255) << 8 | Int(blue * 255)
        return String(format: "#%06x", rgb)
    }
    
    convenience init?(hex: String) {
        let hexString = hex.replacingOccurrences(of: "#", with: "")
        guard hexString.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// MARK: - MUDTheme Structure (for Phase 2 compatibility)

struct MUDTheme {
    let name: String
    let displayName: String
    let terminalTextColor: UIColor
    let terminalBackgroundColor: UIColor
    let linkColor: UIColor
    let fontName: String
    let fontSize: CGFloat
}

// MARK: - ThemeManager

class ThemeManager {
    static let shared = ThemeManager()
    
    // MARK: - Theme Properties
    
    struct Theme {
        let name: String
        let fontColor: UIColor
        let backgroundColor: UIColor
        let linkColor: UIColor
        let isDark: Bool
        let fontName: String
        let fontSize: CGFloat
    }
    
    // MARK: - Default Themes
    
    private let defaultThemes: [Theme]
    
    private var _currentTheme: Theme
    private var _isGlobal: Bool
    
    var currentTheme: Theme {
        get { return _currentTheme }
        set {
            _currentTheme = newValue
            saveCurrentTheme()
            applyTheme()
        }
    }
    
    // MARK: - Initialization
    
    // Allow instancing with optional theme index
    init(themeIndex: Int? = nil, fontName: String? = nil, fontSize: CGFloat? = nil, isGlobal: Bool = false) {
        self.defaultThemes = [
            Theme(
                name: "Classic Dark",
                fontColor: .green,
                backgroundColor: .black,
                linkColor: .cyan,
                isDark: true,
                fontName: "Courier",
                fontSize: 12.0
            ),
            Theme(
                name: "Classic Light",
                fontColor: .black,
                backgroundColor: .white,
                linkColor: .blue,
                isDark: false,
                fontName: "Courier",
                fontSize: 12.0
            ),
            Theme(
                name: "Amber Terminal",
                fontColor: UIColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 1.0),
                backgroundColor: .black,
                linkColor: UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),
                isDark: true,
                fontName: "Menlo",
                fontSize: 12.0
            ),
            Theme(
                name: "Matrix",
                fontColor: UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
                backgroundColor: .black,
                linkColor: UIColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0),
                isDark: true,
                fontName: "Courier",
                fontSize: 13.0
            )
        ]
        let idx = themeIndex ?? UserDefaults.standard.object(forKey: "kPrefCurrentThemeIndex") as? Int ?? 0
        let safeIdx = (idx < defaultThemes.count) ? idx : 0
        var theme = defaultThemes[safeIdx]
        if let fontName = fontName ?? UserDefaults.standard.string(forKey: "kPrefCurrentFontName") {
            theme = Theme(
                name: theme.name,
                fontColor: theme.fontColor,
                backgroundColor: theme.backgroundColor,
                linkColor: theme.linkColor,
                isDark: theme.isDark,
                fontName: fontName,
                fontSize: theme.fontSize
            )
        }
        if let fontSize = fontSize ?? UserDefaults.standard.object(forKey: "kPrefCurrentFontSize") as? CGFloat {
            theme = Theme(
                name: theme.name,
                fontColor: theme.fontColor,
                backgroundColor: theme.backgroundColor,
                linkColor: theme.linkColor,
                isDark: theme.isDark,
                fontName: theme.fontName,
                fontSize: fontSize
            )
        }
        self._currentTheme = theme
        self._isGlobal = isGlobal
    }
    
    // Keep the singleton for global use
    private convenience init() {
        self.init(themeIndex: nil, fontName: nil, fontSize: nil, isGlobal: true)
    }
    
    // MARK: - Theme Management
    
    func setupAppearance() {
        applyTheme()
    }
    
    private func applyTheme() {
        // Only apply global appearance settings if this is the global ThemeManager instance
        if _isGlobal {
            // Apply global appearance settings
            let nav = UINavigationBar.appearance()
            nav.tintColor = currentTheme.linkColor
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithDefaultBackground()
            navAppearance.backgroundColor = UIColor.secondarySystemGroupedBackground
            navAppearance.titleTextAttributes = [
                .foregroundColor: currentTheme.fontColor,
                .font: UIFont(name: currentTheme.fontName, size: 18.0) ?? UIFont.systemFont(ofSize: 18.0)
            ]
            nav.standardAppearance = navAppearance
            nav.scrollEdgeAppearance = navAppearance

            let toolbar = UIToolbar.appearance()
            let toolbarAppearance = UIToolbarAppearance()
            toolbarAppearance.configureWithDefaultBackground()
            toolbar.standardAppearance = toolbarAppearance
            toolbar.scrollEdgeAppearance = toolbarAppearance
            toolbar.tintColor = currentTheme.linkColor

            let tab = UITabBar.appearance()
            let tabAppearance = UITabBarAppearance()
            tabAppearance.configureWithDefaultBackground()
            tab.standardAppearance = tabAppearance
            tab.scrollEdgeAppearance = tabAppearance
            tab.tintColor = currentTheme.linkColor
            
            // Set status bar style based on theme
            if #available(iOS 13.0, *) {
                // Modern status bar handling - notify view controllers to update their status bar style
                NotificationCenter.default.post(name: .statusBarStyleShouldUpdate, object: currentTheme.isDark)
            }
            
            // Post notification for theme change
            NotificationCenter.default.post(name: .themeDidChange, object: currentTheme)
        }
    }
    
    private func saveCurrentTheme() {
        if let index = defaultThemes.firstIndex(where: { $0.name == currentTheme.name }) {
            UserDefaults.standard.set(index, forKey: "kPrefCurrentThemeIndex")
        }
        UserDefaults.standard.set(currentTheme.fontName, forKey: "kPrefCurrentFontName")
        UserDefaults.standard.set(currentTheme.fontSize, forKey: "kPrefCurrentFontSize")
    }
    
    // MARK: - Font Management
    
    func updateFont(name: String, size: CGFloat) {
        _currentTheme = Theme(
            name: currentTheme.name,
            fontColor: currentTheme.fontColor,
            backgroundColor: currentTheme.backgroundColor,
            linkColor: currentTheme.linkColor,
            isDark: currentTheme.isDark,
            fontName: name,
            fontSize: size
        )
        saveCurrentTheme()
        applyTheme()
    }
    
    func availableFonts() -> [String] {
        // Return list of monospace fonts suitable for terminal display
        // Prefer built-in system monospace fonts to avoid missing bundled files
        return [
            "Menlo",
            "Courier New",
            "Courier",
            "Monaco",
            "SF Mono",
            "American Typewriter"
        ].filter { UIFont(name: $0, size: 12) != nil }
    }
    
    // MARK: - Theme Access
    
    func allThemes() -> [Theme] {
        return defaultThemes
    }
    
    func setTheme(at index: Int) {
        guard index < defaultThemes.count else { return }
        currentTheme = defaultThemes[index]
    }
    
    // MARK: - Phase 2 Theme Methods
    
    func allAvailableThemes() -> [MUDTheme] {
        // Convert current Theme structure to MUDTheme for compatibility
        return defaultThemes.map { theme in
            MUDTheme(
                name: theme.name,
                displayName: theme.name,
                terminalTextColor: theme.fontColor,
                terminalBackgroundColor: theme.backgroundColor,
                linkColor: theme.linkColor,
                fontName: theme.fontName,
                fontSize: theme.fontSize
            )
        }
    }
    
    func setTheme(_ theme: MUDTheme) {
        // Convert MUDTheme back to internal Theme structure
        _currentTheme = Theme(
            name: theme.name,
            fontColor: theme.terminalTextColor,
            backgroundColor: theme.terminalBackgroundColor,
            linkColor: theme.linkColor,
            isDark: theme.terminalBackgroundColor.isDarkColor,
            fontName: theme.fontName,
            fontSize: theme.fontSize
        )
        saveCurrentTheme()
        applyTheme()
    }
    
    func setFontSize(_ size: CGFloat) {
        updateFont(name: currentTheme.fontName, size: size)
    }
    
    func setFontName(_ name: String) {
        updateFont(name: name, size: currentTheme.fontSize)
    }
    
    func refreshTheme() {
        applyTheme()
    }
    
    func updateForSystemAppearance() {
        // Update theme based on system appearance if follow system setting is enabled
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.followSystemAppearance) {
            // Logic to switch themes based on system appearance
            if #available(iOS 12.0, *) {
                let isDarkMode = UIScreen.main.traitCollection.userInterfaceStyle == .dark
                if isDarkMode && !currentTheme.isDark {
                    // Switch to a dark theme
                    if let darkTheme = defaultThemes.first(where: { $0.isDark }) {
                        currentTheme = darkTheme
                    }
                } else if !isDarkMode && currentTheme.isDark {
                    // Switch to a light theme
                    if let lightTheme = defaultThemes.first(where: { !$0.isDark }) {
                        currentTheme = lightTheme
                    }
                }
            }
        }
    }
    
    // MARK: - Convenience Properties
    
    var terminalFont: UIFont {
        let baseFont = UIFont(name: currentTheme.fontName, size: currentTheme.fontSize) ?? 
                      UIFont.monospacedSystemFont(ofSize: currentTheme.fontSize, weight: .regular)
        
        // Support Dynamic Type scaling
        if #available(iOS 11.0, *) {
            let fontMetrics = UIFontMetrics(forTextStyle: .body)
            return fontMetrics.scaledFont(for: baseFont)
        } else {
            return baseFont
        }
    }
    
    var terminalTextColor: UIColor {
        return currentTheme.fontColor
    }
    
    var terminalBackgroundColor: UIColor {
        return currentTheme.backgroundColor
    }
    
    var linkColor: UIColor {
        return currentTheme.linkColor
    }
    
    var isDarkTheme: Bool {
        return currentTheme.isDark
    }
    
    // MARK: - Custom Theme Support
    
    func addCustomTheme(_ customTheme: CustomTheme) {
        // Save the custom theme to UserDefaults
        let themeData = customTheme.toThemeData()
        UserDefaults.standard.set(themeData, forKey: "CustomTheme_\(customTheme.name)")
        
        // Post notification that themes have changed
        NotificationCenter.default.post(name: .themeDidChange, object: self)
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let themeDidChange = Notification.Name("ThemeDidChangeNotification")
    static let statusBarStyleShouldUpdate = Notification.Name("StatusBarStyleShouldUpdateNotification")
} 