import UIKit
import Foundation

class ANSIProcessor {
    
    private let themeManager: ThemeManager
    
    // MARK: - Initialization
    
    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        self.currentAttributes = TextAttributes(
            foregroundColor: themeManager.terminalTextColor,
            backgroundColor: themeManager.terminalBackgroundColor
        )
    }
    
    // MARK: - Text Attributes
    
    private struct TextAttributes {
        var foregroundColor: UIColor
        var backgroundColor: UIColor
        var isBold: Bool = false
        var isItalic: Bool = false
        var isUnderlined: Bool = false
        var isStrikethrough: Bool = false
        var isInverse: Bool = false
        var isDim: Bool = false
        
        func toAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
            // Compute effective colors with inverse and dim handling
            let baseForeground = isInverse ? backgroundColor : foregroundColor
            let baseBackground = isInverse ? foregroundColor : backgroundColor
            let effectiveForeground: UIColor = isDim ? baseForeground.withAlphaComponent(0.75) : baseForeground
            
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: effectiveForeground,
                .backgroundColor: baseBackground
            ]
            
            // Handle font styling
            var fontDescriptor = font.fontDescriptor
            var traits: UIFontDescriptor.SymbolicTraits = []
            
            if isBold {
                traits.insert(.traitBold)
            }
            
            if isItalic {
                traits.insert(.traitItalic)
            }
            
            if !traits.isEmpty {
                fontDescriptor = fontDescriptor.withSymbolicTraits(traits) ?? fontDescriptor
            }
            
            attributes[.font] = UIFont(descriptor: fontDescriptor, size: font.pointSize)
            
            // Handle underline
            if isUnderlined {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            
            // Handle strikethrough
            if isStrikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            
            return attributes
        }
    }
    
    // MARK: - Properties
    
    private var currentAttributes: TextAttributes
    private let ansiPattern = "\\x1B\\[[0-9;]*[a-zA-Z]"
    private lazy var ansiRegex: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: ansiPattern, options: [])
    }()
    
    // Additional regex for other escape sequences
    private let escapePattern = "\\x1B[\\[\\(\\)][^a-zA-Z]*[a-zA-Z]?"
    private lazy var escapeRegex: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: escapePattern, options: [])
    }()
    
    // MARK: - Theme Refresh
    
    func refreshThemeColors() {
        currentAttributes.foregroundColor = themeManager.terminalTextColor
        currentAttributes.backgroundColor = themeManager.terminalBackgroundColor
    }

    // Reset current SGR/text attributes back to theme defaults
    private func resetAttributes() {
        currentAttributes = TextAttributes(
            foregroundColor: themeManager.terminalTextColor,
            backgroundColor: themeManager.terminalBackgroundColor
        )
    }
    
    // MARK: - Processing
    
    func processText(_ text: String, font: UIFont? = nil) -> NSAttributedString {
        // Fast path: empty
        guard !text.isEmpty else { return NSAttributedString() }
        
        let effectiveFont = font ?? themeManager.terminalFont
        resetAttributes()
        
        let cleanedText = cleanTextForProcessing(text)
        
        // Fast path: plain text
        if cleanedText.range(of: "\u{1B}[") == nil && cleanedText.range(of: "@") == nil {
            return NSAttributedString(string: cleanedText, attributes: currentAttributes.toAttributes(font: effectiveFont))
        }
        
        // Process tbaMUD @ color codes first, then standard ANSI
        let tbaMUDProcessed = processTbaMUDColors(cleanedText)
        
        // Find all ANSI escape sequences
        guard let regex = ansiRegex else {
            return NSAttributedString(string: tbaMUDProcessed, attributes: currentAttributes.toAttributes(font: effectiveFont))
        }
        
        // Convert to NSString for regex processing (handles UTF-8 properly)
        let nsText = tbaMUDProcessed as NSString
        let range = NSRange(location: 0, length: nsText.length)
        
        // Get all ANSI matches
        let ansiMatches = regex.matches(in: tbaMUDProcessed, options: [], range: range)
        
        // Get all other escape sequence matches
        let escapeMatches = escapeRegex?.matches(in: tbaMUDProcessed, options: [], range: range) ?? []
        
        // Combine and sort all matches
        let allMatches = (ansiMatches + escapeMatches).sorted { $0.range.location < $1.range.location }
        
        var lastLocation = 0
        let mutableString = NSMutableAttributedString()
        
        for match in allMatches {
            // Add text before the escape sequence
            if match.range.location > lastLocation {
                let textRange = NSRange(location: lastLocation, length: match.range.location - lastLocation)
                let substring = nsText.substring(with: textRange)
                let attributes = currentAttributes.toAttributes(font: effectiveFont)
                mutableString.append(NSAttributedString(string: substring, attributes: attributes))
            }
            
            // Process the escape sequence
            let escapeCode = nsText.substring(with: match.range)
            if escapeCode.contains("[") {
                // This is an ANSI sequence
                processANSICode(escapeCode)
            }
            // Other escape sequences are just filtered out
            
            lastLocation = match.range.location + match.range.length
        }
        
        // Add remaining text
        if lastLocation < nsText.length {
            let remainingRange = NSRange(location: lastLocation, length: nsText.length - lastLocation)
            let substring = nsText.substring(with: remainingRange)
            let attributes = currentAttributes.toAttributes(font: effectiveFont)
            mutableString.append(NSAttributedString(string: substring, attributes: attributes))
        }
        
        return mutableString
    }
    
    private func cleanTextForProcessing(_ text: String) -> String {
        // Remove null characters and other problematic control characters
        var cleaned = text.replacingOccurrences(of: "\0", with: "")
        
        // Remove Unicode replacement characters
        cleaned = cleaned.replacingOccurrences(of: "\u{FFFD}", with: "")
        
        // Remove other problematic Unicode characters that might appear as ??
        cleaned = cleaned.replacingOccurrences(of: "\u{FEFF}", with: "") // BOM
        
        return cleaned
    }
    
    func stripANSICodes(from text: String) -> String {
        guard let regex = ansiRegex else { return text }
        
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
    
    // MARK: - Private Methods
    
    private func processANSICode(_ code: String) {
        // Remove escape sequence prefix and suffix
        var cleanCode = code.replacingOccurrences(of: "\u{1B}[", with: "")
        
        // Handle different ANSI sequence endings
        if cleanCode.hasSuffix("m") {
            cleanCode = String(cleanCode.dropLast())
        } else if cleanCode.hasSuffix("K") {
            cleanCode = String(cleanCode.dropLast())
            // Handle clear line sequences
            return
        } else if cleanCode.hasSuffix("J") {
            cleanCode = String(cleanCode.dropLast())
            // Handle clear screen sequences
            return
        } else if cleanCode.hasSuffix("H") || cleanCode.hasSuffix("f") {
            // Handle cursor positioning sequences
            return
        } else if cleanCode.hasSuffix("A") || cleanCode.hasSuffix("B") ||
                  cleanCode.hasSuffix("C") || cleanCode.hasSuffix("D") {
            // Handle cursor movement sequences
            return
        } else {
            // Remove any trailing letter for unknown sequences
            cleanCode = cleanCode.replacingOccurrences(of: "[a-zA-Z]$", with: "", options: .regularExpression)
        }
        
        // Handle clear screen codes
        if cleanCode.isEmpty {
            return
        }
        
        // Split multiple codes separated by semicolons
        let codes = cleanCode.components(separatedBy: ";").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        
        // Process codes, handling extended color sequences
        var i = 0
        while i < codes.count {
            let codeValue = codes[i]
            
            // Handle 256-color and RGB color sequences
            if (codeValue == 38 || codeValue == 48) && i + 2 < codes.count && codes[i + 1] == 5 {
                // 256-color mode: ESC[38;5;n or ESC[48;5;n
                let colorIndex = codes[i + 2]
                let color = getXterm256Color(index: colorIndex)
                
                if codeValue == 38 {
                    currentAttributes.foregroundColor = color
                } else {
                    currentAttributes.backgroundColor = color
                }
                
                i += 3 // Skip the next two codes
            } else if (codeValue == 38 || codeValue == 48) && i + 4 < codes.count && codes[i + 1] == 2 {
                // RGB color mode: ESC[38;2;r;g;b or ESC[48;2;r;g;b
                let r = CGFloat(codes[i + 2]) / 255.0
                let g = CGFloat(codes[i + 3]) / 255.0
                let b = CGFloat(codes[i + 4]) / 255.0
                let color = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                
                if codeValue == 38 {
                    currentAttributes.foregroundColor = color
                } else {
                    currentAttributes.backgroundColor = color
                }
                
                i += 5 // Skip the next four codes
            } else {
                // Standard ANSI code
                processANSICodeValue(codeValue)
                i += 1
            }
        }
    }
    
    private func processANSICodeValue(_ code: Int) {
        switch code {
        case 0:
            resetAttributes()
        case 1:
            currentAttributes.isBold = true
        case 2:
            currentAttributes.isDim = true
        case 3:
            currentAttributes.isItalic = true
        case 4:
            currentAttributes.isUnderlined = true
        case 9:
            currentAttributes.isStrikethrough = true
        case 22:
            currentAttributes.isBold = false
            currentAttributes.isDim = false
        case 23:
            currentAttributes.isItalic = false
        case 24:
            currentAttributes.isUnderlined = false
        case 29:
            currentAttributes.isStrikethrough = false
        case 7:
            currentAttributes.isInverse = true
        case 27:
            currentAttributes.isInverse = false
        case 30...37:
            let colorIndex = code - 30
            currentAttributes.foregroundColor = getXterm256Color(index: colorIndex)
        case 40...47:
            let colorIndex = code - 40
            currentAttributes.backgroundColor = getXterm256Color(index: colorIndex)
        case 90...97:
            currentAttributes.foregroundColor = getXterm256Color(index: code - 90 + 8)
        case 100...107:
            currentAttributes.backgroundColor = getXterm256Color(index: code - 100 + 8)
        case 39:
            currentAttributes.foregroundColor = themeManager.terminalTextColor
        case 49:
            currentAttributes.backgroundColor = themeManager.terminalBackgroundColor
        default:
            break
        }
    }
    
    // MARK: - Traditional ANSI Colors
    
    // Traditional ANSI color palette (more muted, terminal-appropriate colors)
    private static let traditionalANSIColors: [UIColor] = {
        return [
            UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),       // 0: black
            UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0),       // 1: red
            UIColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0),       // 2: green
            UIColor(red: 0.8, green: 0.8, blue: 0.0, alpha: 1.0),       // 3: yellow
            UIColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0),       // 4: blue
            UIColor(red: 0.8, green: 0.0, blue: 0.8, alpha: 1.0),       // 5: magenta
            UIColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1.0),       // 6: cyan
            UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0),       // 7: white
            UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0),       // 8: bright black (dark gray)
            UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),       // 9: bright red
            UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),       // 10: bright green
            UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),       // 11: bright yellow
            UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0),       // 12: bright blue
            UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0),       // 13: bright magenta
            UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0),       // 14: bright cyan
            UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)        // 15: bright white
        ]
    }()
    
    private func getTraditionalANSIColor(index: Int) -> UIColor {
        guard index >= 0 && index < 16 else {
            return themeManager.terminalTextColor
        }
        return ANSIProcessor.traditionalANSIColors[index]
    }

    // MARK: - XTERM 256-Color Support
    
    // Complete XTERM 256-color palette
    private static let xterm256Colors: [UIColor] = {
        var colors: [UIColor] = []
        
        // System colors (0-15): Standard ANSI colors from the xterm palette
        colors.append(UIColor(red: 0/255, green: 0/255, blue: 0/255, alpha: 1.0))       // 0: black
        colors.append(UIColor(red: 205/255, green: 0/255, blue: 0/255, alpha: 1.0))     // 1: red
        colors.append(UIColor(red: 0/255, green: 205/255, blue: 0/255, alpha: 1.0))     // 2: green
        colors.append(UIColor(red: 205/255, green: 205/255, blue: 0/255, alpha: 1.0))   // 3: yellow
        colors.append(UIColor(red: 0/255, green: 0/255, blue: 238/255, alpha: 1.0))     // 4: blue
        colors.append(UIColor(red: 205/255, green: 0/255, blue: 205/255, alpha: 1.0))   // 5: magenta
        colors.append(UIColor(red: 0/255, green: 205/255, blue: 205/255, alpha: 1.0))   // 6: cyan
        colors.append(UIColor(red: 229/255, green: 229/255, blue: 229/255, alpha: 1.0)) // 7: white
        colors.append(UIColor(red: 127/255, green: 127/255, blue: 127/255, alpha: 1.0)) // 8: bright black
        colors.append(UIColor(red: 255/255, green: 0/255, blue: 0/255, alpha: 1.0))     // 9: bright red
        colors.append(UIColor(red: 0/255, green: 255/255, blue: 0/255, alpha: 1.0))     // 10: bright green
        colors.append(UIColor(red: 255/255, green: 255/255, blue: 0/255, alpha: 1.0))   // 11: bright yellow
        colors.append(UIColor(red: 92/255, green: 92/255, blue: 255/255, alpha: 1.0))   // 12: bright blue
        colors.append(UIColor(red: 255/255, green: 0/255, blue: 255/255, alpha: 1.0))   // 13: bright magenta
        colors.append(UIColor(red: 0/255, green: 255/255, blue: 255/255, alpha: 1.0))   // 14: bright cyan
        colors.append(UIColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1.0)) // 15: bright white

        // Color cube (16-231): 6x6x6 RGB cube
        let colorLevels: [CGFloat] = [0, 95, 135, 175, 215, 255]
        for r_idx in 0..<6 {
            for g_idx in 0..<6 {
                for b_idx in 0..<6 {
                    let red = colorLevels[r_idx] / 255.0
                    let green = colorLevels[g_idx] / 255.0
                    let blue = colorLevels[b_idx] / 255.0
                    colors.append(UIColor(red: red, green: green, blue: blue, alpha: 1.0))
                }
            }
        }
        
        // Grayscale (232-255): 24 levels from black to white
        for i in 0..<24 {
            let gray = (CGFloat(8 + i * 10)) / 255.0
            colors.append(UIColor(red: gray, green: gray, blue: gray, alpha: 1.0))
        }
        
        return colors
    }()
    
    private func getXterm256Color(index: Int) -> UIColor {
        guard index >= 0 && index < 256 else {
            return themeManager.terminalTextColor
        }
        return ANSIProcessor.xterm256Colors[index]
    }
    
    // MARK: - tbaMUD Color Code Support
    
    private func processTbaMUDColors(_ text: String) -> String {
        var processedText = text
        
        // First process Xterm 256-color codes: @[F522] format
        processedText = processTbaMUDXtermColors(processedText)
        
        // Then process basic tbaMUD @ color codes
        let tbaMUDColors: [String: String] = [
            "@k": "\u{1B}[30m",     // black
            "@r": "\u{1B}[31m",     // red
            "@g": "\u{1B}[32m",     // green
            "@y": "\u{1B}[33m",     // yellow
            "@b": "\u{1B}[34m",     // blue
            "@m": "\u{1B}[35m",     // magenta
            "@c": "\u{1B}[36m",     // cyan
            "@w": "\u{1B}[37m",     // white
            "@K": "\u{1B}[1;30m",   // bold black (dark gray)
            "@R": "\u{1B}[1;31m",   // bold red
            "@G": "\u{1B}[1;32m",   // bold green
            "@Y": "\u{1B}[1;33m",   // bold yellow
            "@B": "\u{1B}[1;34m",   // bold blue
            "@M": "\u{1B}[1;35m",   // bold magenta
            "@C": "\u{1B}[1;36m",   // bold cyan
            "@W": "\u{1B}[1;37m",   // bold white
            "@n": "\u{1B}[0m",      // normal/reset
            "@N": "\u{1B}[0m",      // normal/reset (alternate)
            "@d": "\u{1B}[2m",      // dim
            "@u": "\u{1B}[4m",      // underline
            "@f": "\u{1B}[5m",      // flash/blink
            "@i": "\u{1B}[7m",      // inverse
            "@s": "\u{1B}[9m",      // strikethrough
            "@@": "@"               // literal @ symbol
        ]
        
        // Process each tbaMUD basic color code
        for (tbaMUDCode, ansiCode) in tbaMUDColors {
            processedText = processedText.replacingOccurrences(of: tbaMUDCode, with: ansiCode)
        }
        
        return processedText
    }
    
    private func processTbaMUDXtermColors(_ text: String) -> String {
        // Handle tbaMUD Xterm 256-color codes: @[F522], @[B123], etc.
        // F = foreground, B = background, followed by 3-digit color code
        
        let xtermPattern = "@\\[([FB])(\\d{3})\\]"
        
        guard let regex = try? NSRegularExpression(pattern: xtermPattern, options: []) else {
            return text
        }
        
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        
        // Process matches in reverse order to avoid range issues
        let matches = regex.matches(in: text, options: [], range: range).reversed()
        var result = text
        
        for match in matches {
            let type = nsText.substring(with: match.range(at: 1))
            let code = nsText.substring(with: match.range(at: 2))
            
            let prefix = (type == "F") ? "38;5" : "48;5"
            let ansiCode = "\u{1B}[\(prefix);\(code)m"
            
            if let r = Range(match.range, in: result) {
                result.replaceSubrange(r, with: ansiCode)
            }
        }
        
        return result
    }
}

// MARK: - UIColor Extension

extension UIColor {
    var rgbString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return "\(Int(red * 255)),\(Int(green * 255)),\(Int(blue * 255))"
    }
} 