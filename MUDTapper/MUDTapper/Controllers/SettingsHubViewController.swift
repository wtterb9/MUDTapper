import UIKit
import CoreData

/// A full-screen, Settings-style hub that replaces the legacy action-sheet menus
class SettingsHubViewController: SettingsViewController {
    private let world: World?
    private let themeManager = ThemeManager.shared

    init(world: World?) {
        self.world = world
        super.init(title: "⚙️ Settings")
    }

    required init?(coder: NSCoder) {
        self.world = nil
        super.init(coder: coder)
    }

    override func setupSections() {
        var sections: [SettingsSection] = []

        if let world = world {
            sections.append(createWorldSection(world: world))
            sections.append(createAutomationSection(world: world))
        }

        sections.append(createAppearanceSection())
        sections.append(createInputSection())
        sections.append(createNetworkingSection())
        sections.append(createLoggingSection())
        sections.append(createAboutSection())

        setSections(sections)
    }

    private func createWorldSection(world: World) -> SettingsSection {
        let items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "📝 Edit World Info",
                accessibilityHint: "Edit name, host, and port"
            ) { [weak self] in
                let vc = WorldEditController(world: world)
                vc.delegate = self as? WorldEditControllerDelegate
                return vc
            },
            NavigationSettingsItem(
                title: "🌍 World Management",
                accessibilityHint: "Browse and manage all worlds"
            ) {
                EnhancedWorldManagementViewController()
            }
        ]

        return SettingsSection(title: "World", items: items)
    }

    private func createAutomationSection(world: World) -> SettingsSection {
        let items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "🤖 Advanced Automation",
                accessibilityHint: "Manage triggers, aliases, gags, and tickers"
            ) {
                AdvancedAutomationViewController(world: world)
            }
        ]
        return SettingsSection(title: "Automation", items: items)
    }

    private func createAppearanceSection() -> SettingsSection {
        let items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "🎨 Themes & Appearance",
                detail: themeManager.currentTheme.name,
                accessibilityHint: "Colors, fonts, display"
            ) {
                ThemeSettingsViewController()
            }
        ]
        return SettingsSection(title: "Appearance", items: items)
    }

    private func createInputSection() -> SettingsSection {
        let items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "⌨️ Input & Controls",
                accessibilityHint: "Keyboard, commands, radial controls"
            ) {
                InputSettingsViewController()
            }
        ]
        return SettingsSection(title: "Input", items: items)
    }

    private func createNetworkingSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "Enable GMCP",
                accessibilityHint: "Negotiates GMCP and sends Core.Hello",
                userDefaultsKey: "Networking.GMCPEnabled",
                defaultValue: true
            ),
            ToggleSettingsItem(
                title: "Enable MSDP",
                accessibilityHint: "Negotiates MSDP and sends capabilities",
                userDefaultsKey: "Networking.MSDPEnabled",
                defaultValue: true
            ),
            ToggleSettingsItem(
                title: "Enable MCCP (Compression)",
                accessibilityHint: "Accept server compression to save bandwidth",
                userDefaultsKey: "Networking.MCCPEnabled",
                defaultValue: true
            ),
            ToggleSettingsItem(
                title: "Auto‑reconnect",
                accessibilityHint: "Reconnects automatically if disconnected",
                userDefaultsKey: "Networking.AutoReconnectEnabled",
                defaultValue: true
            )
        ]
        return SettingsSection(title: "Networking", footer: "These settings apply to all worlds.", items: items)
    }

    private func createLoggingSection() -> SettingsSection {
        let items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "📁 Session Logs",
                accessibilityHint: "View and manage logs"
            ) {
                LogManagerViewController()
            }
        ]
        return SettingsSection(title: "Logging & Data", items: items)
    }

    private func createAboutSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ActionSettingsItem(
                title: "📖 User Guide",
                accessibilityHint: "Read how to use the app"
            ) { [weak self] in
                self?.showSimpleInfo(title: "📖 User Guide", message: "Coming soon. Visit the repository for up-to-date docs.")
            },
            ActionSettingsItem(
                title: "ℹ️ About",
                accessibilityHint: "App version and info"
            ) { [weak self] in
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                self?.showSimpleInfo(title: "About MUDTapper", message: "Version: \(version)")
            }
        ]
        return SettingsSection(title: "Help & About", items: items)
    }

    private func showSimpleInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}


