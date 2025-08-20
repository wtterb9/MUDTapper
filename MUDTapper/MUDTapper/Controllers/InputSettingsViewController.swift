import UIKit

class InputSettingsViewController: SettingsViewController {
    
    // MARK: - Properties
    
    weak var clientViewController: ClientViewController?
    
    // MARK: - Initialization
    
    init(clientViewController: ClientViewController? = nil) {
        self.clientViewController = clientViewController
        super.init(title: "⌨️ Input Settings")
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - Setup
    
    override func setupSections() {
        let sections: [SettingsSection] = [
            createInputBehaviorSection(),
            createKeyboardSection(),
            createRadialControlsSection(),
            createCommandSection(),
            createNetworkSection()
        ]
        
        setSections(sections)
    }
    
    // MARK: - Section Creation
    
    private func createInputBehaviorSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "Local Echo",
                accessibilityLabel: "Local Echo",
                accessibilityHint: "Show commands you type locally before sending to server",
                userDefaultsKey: UserDefaultsKeys.localEcho,
                onToggle: { enabled in
                    // Could notify client to update echo behavior
                }
            ),
            ToggleSettingsItem(
                title: "Auto-send Commands",
                accessibilityLabel: "Auto-send Commands",
                accessibilityHint: "Automatically send commands without requiring return key",
                userDefaultsKey: UserDefaultsKeys.autoSendCommands,
                defaultValue: false
            ),
            ToggleSettingsItem(
                title: "Command History",
                accessibilityLabel: "Command History",
                accessibilityHint: "Save command history for easy recall",
                userDefaultsKey: UserDefaultsKeys.saveCommandHistory,
                defaultValue: true
            )
        ]
        
        return SettingsSection(
            title: "Input Behavior",
            footer: "Configure how commands are handled and displayed",
            items: items
        )
    }
    
    private func createKeyboardSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "Autocorrect",
                accessibilityLabel: "Autocorrect",
                accessibilityHint: "Enable iOS autocorrect for command input",
                userDefaultsKey: UserDefaultsKeys.autocorrect
            ),
            ToggleSettingsItem(
                title: "Auto-Capitalization",
                accessibilityLabel: "Auto-Capitalization",
                accessibilityHint: "Automatically capitalize first letter of commands",
                userDefaultsKey: UserDefaultsKeys.autoCapitalization,
                defaultValue: false
            ),
            ToggleSettingsItem(
                title: "Smart Punctuation",
                accessibilityLabel: "Smart Punctuation",
                accessibilityHint: "Use smart quotes and dashes",
                userDefaultsKey: UserDefaultsKeys.smartPunctuation,
                defaultValue: false
            ),
            NavigationSettingsItem(
                title: "Custom Keyboard",
                detail: "MUDTapper Keyboard",
                accessibilityLabel: "Custom Keyboard Settings",
                accessibilityHint: "Configure the custom MUDTapper keyboard",
                destination: { CustomKeyboardSettingsViewController(title: "Custom Keyboard") }
            )
        ]
        
        return SettingsSection(
            title: "Keyboard",
            footer: "Adjust keyboard behavior and settings",
            items: items
        )
    }

    private func createRadialControlsSection() -> SettingsSection {
        let currentStyle = RadialControl.radialControlStyle()
        var items: [SettingsItem] = [
            NavigationSettingsItem(
                title: "Left Radial Position",
                accessibilityHint: "Choose position for left radial controls"
            ) { [weak self] in
                self?.presentRadialPositionSelector(isLeftRadial: true)
                return UIViewController() // placeholder; modal will present
            },
            NavigationSettingsItem(
                title: "Right Radial Position",
                accessibilityHint: "Choose position for right radial controls"
            ) { [weak self] in
                self?.presentRadialPositionSelector(isLeftRadial: false)
                return UIViewController()
            },
            NavigationSettingsItem(
                title: "Radial Control Style",
                detail: currentStyle.displayName,
                accessibilityHint: "Choose a visual style for radial controls"
            ) { [weak self] in
                self?.presentRadialStyleSelector()
                return UIViewController()
            },
            ToggleSettingsItem(
                title: "Show Labels",
                accessibilityHint: "Show direction labels on radial controls",
                userDefaultsKey: UserDefaultsKeys.radialControlLabelsVisible,
                defaultValue: false
            )
        ]

        // Always expose command customization here (no dependency on client context)
        items.append(NavigationSettingsItem(
            title: "Customize Left Radial Commands",
            accessibilityHint: "Set commands for each left radial direction"
        ) { [weak self] in
            self?.showRadialCommandCustomization(for: 0)
            return UIViewController()
        })
        items.append(NavigationSettingsItem(
            title: "Customize Right Radial Commands",
            accessibilityHint: "Set commands for each right radial direction"
        ) { [weak self] in
            self?.showRadialCommandCustomization(for: 1)
            return UIViewController()
        })
        items.append(ActionSettingsItem(
            title: "Reset All Radial Commands",
            accessibilityLabel: "Reset All Radial Commands",
            accessibilityHint: "Restore default commands for both radials",
            style: .destructive
        ) { [weak self] in
            self?.resetAllRadialCommands()
        })
        
        return SettingsSection(
            title: "Radial Controls",
            footer: "Customize radial positions, style, labels, and per-direction commands",
            items: items
        )
    }

    // MARK: - Radial Commands (local implementation)

    private func showRadialCommandCustomization(for buttonIndex: Int) {
        let buttonName = buttonIndex == 0 ? "Left" : "Right"
        let alert = UIAlertController(title: "\u{1F3AE} \(buttonName) Radial Commands", message: "Customize commands for each direction", preferredStyle: .actionSheet)

        for direction in RadialDirection.allCases {
            let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
            let currentCommand = UserDefaults.standard.string(forKey: key) ?? direction.defaultCommand
            let title = "\(direction.rawValue.capitalized): \(currentCommand)"
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.editRadialCommand(for: buttonIndex, direction: direction)
            })
        }

        alert.addAction(UIAlertAction(title: "\u{1F501} Reset to Defaults", style: .destructive) { [weak self] _ in
            self?.resetRadialButton(buttonIndex)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func editRadialCommand(for buttonIndex: Int, direction: RadialDirection) {
        let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
        let currentCommand = UserDefaults.standard.string(forKey: key) ?? direction.defaultCommand
        let buttonName = buttonIndex == 0 ? "Left" : "Right"

        let alert = UIAlertController(title: "✏️ Edit \(direction.rawValue.capitalized) Command", message: "\(buttonName) Radial\nCurrent: \(currentCommand)", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Enter command"
            tf.text = currentCommand
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let newText = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if newText.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(newText, forKey: key)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func resetRadialButton(_ buttonIndex: Int) {
        for direction in RadialDirection.allCases {
            let key = "RadialButton\(buttonIndex)_\(direction.rawValue)"
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func resetAllRadialCommands() {
        let alert = UIAlertController(title: "Reset Radial Commands", message: "This will reset all radial button commands to defaults.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { _ in
            for buttonIndex in 0..<2 { self.resetRadialButton(buttonIndex) }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Radial Controls Helpers (modal presenters)
    private func presentRadialPositionSelector(isLeftRadial: Bool) {
        let side = isLeftRadial ? "Left" : "Right"
        let alert = UIAlertController(title: "\(side) Radial Position", message: "Choose position", preferredStyle: .actionSheet)
        
        func set(_ position: String) {
            let key = isLeftRadial ? UserDefaultsKeys.leftRadialPosition : UserDefaultsKeys.rightRadialPosition
            UserDefaults.standard.set(position, forKey: key)
        }
        
        alert.addAction(UIAlertAction(title: "Top", style: .default) { _ in set("top") })
        alert.addAction(UIAlertAction(title: "Middle", style: .default) { _ in set("middle") })
        alert.addAction(UIAlertAction(title: "Bottom", style: .default) { _ in set("bottom") })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func presentRadialStyleSelector() {
        let alert = UIAlertController(title: "Radial Control Style", message: "Choose a style", preferredStyle: .actionSheet)
        let current = RadialControl.radialControlStyle()
        
        for style in RadialControlStyle.allCases {
            let title = style.displayName + (style == current ? " ✓" : "")
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                RadialControl.setRadialControlStyle(style)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func createCommandSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ActionSettingsItem(
                title: "View Command History",
                accessibilityLabel: "View Command History",
                accessibilityHint: "Browse and manage saved commands"
            ) { [weak self] in
                self?.showCommandHistory()
            },
            ActionSettingsItem(
                title: "Clear Command History",
                accessibilityLabel: "Clear Command History",
                accessibilityHint: "Remove all saved commands",
                style: .destructive
            ) { [weak self] in
                self?.clearCommandHistory()
            },
            ToggleSettingsItem(
                title: "Command Completion",
                accessibilityLabel: "Command Completion",
                accessibilityHint: "Suggest completions while typing",
                userDefaultsKey: UserDefaultsKeys.commandCompletion,
                defaultValue: true
            )
        ]
        
        return SettingsSection(
            title: "Commands",
            footer: "Manage command history and completion",
            items: items
        )
    }
    
    private func createNetworkSection() -> SettingsSection {
        var items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "Connect on Startup",
                accessibilityLabel: "Connect on Startup",
                accessibilityHint: "Automatically connect to the last world when app starts",
                userDefaultsKey: UserDefaultsKeys.connectOnStartup
            ),
            ToggleSettingsItem(
                title: "Auto-Reconnect",
                accessibilityLabel: "Auto-Reconnect",
                accessibilityHint: "Automatically reconnect when connection is lost",
                userDefaultsKey: UserDefaultsKeys.autoReconnect,
                defaultValue: true
            ),
            ActionSettingsItem(
                title: "Connection Timeout",
                accessibilityLabel: "Connection Timeout Settings",
                accessibilityHint: "Configure connection timeout duration"
            ) { [weak self] in
                self?.showTimeoutSettings()
            }
        ]

        // Move Background Audio here from legacy action sheet
        items.append(
            ToggleSettingsItem(
                title: "Background Audio",
                accessibilityLabel: "Background Audio",
                accessibilityHint: "Keep minimal audio active to help maintain connections in background",
                userDefaultsKey: UserDefaultsKeys.backgroundAudioEnabled,
                defaultValue: true
            )
        )
        
        return SettingsSection(
            title: "Network",
            footer: "Configure connection behavior",
            items: items
        )
    }
    
    // MARK: - Action Methods
    
    private func showCommandHistory() {
        let historyVC = CommandHistoryViewController()
        let navController = UINavigationController(rootViewController: historyVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func clearCommandHistory() {
        let alert = UIAlertController(
            title: "Clear Command History",
            message: "Are you sure you want to clear all saved commands? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            // Clear command history
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.commandHistory)
            
            // Show confirmation
            self.showAlert(title: "History Cleared", message: "All command history has been removed.")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showTimeoutSettings() {
        let alert = UIAlertController(
            title: "Connection Timeout",
            message: "Set the connection timeout in seconds (5-60)",
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = "Timeout (seconds)"
            textField.keyboardType = .numberPad
            let currentTimeout = UserDefaults.standard.integer(forKey: UserDefaultsKeys.connectionTimeout)
            textField.text = currentTimeout > 0 ? "\(currentTimeout)" : "30"
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            guard let text = alert.textFields?.first?.text,
                  let timeout = Int(text),
                  timeout >= 5 && timeout <= 60 else {
                self.showAlert(title: "Invalid Input", message: "Please enter a timeout between 5 and 60 seconds.")
                return
            }
            
            UserDefaults.standard.set(timeout, forKey: UserDefaultsKeys.connectionTimeout)
            self.showAlert(title: "Timeout Updated", message: "Connection timeout set to \(timeout) seconds.")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Command History View Controller

class CommandHistoryViewController: UIViewController {
    
    private var tableView: UITableView!
    private var commands: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Command History"
        setupUI()
        loadCommands()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear All",
            style: .plain,
            target: self,
            action: #selector(clearAllTapped)
        )
        
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadCommands() {
        commands = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.commandHistory) ?? []
        tableView.reloadData()
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func clearAllTapped() {
        let alert = UIAlertController(
            title: "Clear All Commands",
            message: "Are you sure you want to clear all command history?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.commandHistory)
            self.commands.removeAll()
            self.tableView.reloadData()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

extension CommandHistoryViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return commands.isEmpty ? 1 : commands.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        
        if commands.isEmpty {
            cell.textLabel?.text = "No commands in history"
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            cell.textLabel?.text = commands[indexPath.row]
            cell.textLabel?.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete && !commands.isEmpty {
            commands.remove(at: indexPath.row)
            UserDefaults.standard.set(commands, forKey: UserDefaultsKeys.commandHistory)
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            if commands.isEmpty {
                tableView.reloadData() // Show "No commands" message
            }
        }
    }
}

// MARK: - Custom Keyboard Settings View Controller

class CustomKeyboardSettingsViewController: SettingsViewController {
    
    override func setupSections() {
        let sections: [SettingsSection] = [
            createKeyboardLayoutSection(),
            createSpecialKeysSection()
        ]
        
        setSections(sections)
    }
    
    private func createKeyboardLayoutSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "Number Row",
                accessibilityHint: "Show number row above keyboard",
                userDefaultsKey: UserDefaultsKeys.showNumberRow,
                defaultValue: true
            ),
            ToggleSettingsItem(
                title: "Punctuation Row",
                accessibilityHint: "Show punctuation marks row",
                userDefaultsKey: UserDefaultsKeys.showPunctuationRow,
                defaultValue: true
            )
        ]
        
        return SettingsSection(
            title: "Layout",
            footer: "Configure which rows are visible on the custom keyboard",
            items: items
        )
    }
    
    private func createSpecialKeysSection() -> SettingsSection {
        let items: [SettingsItem] = [
            ToggleSettingsItem(
                title: "Tab Key",
                accessibilityHint: "Include tab key for command completion",
                userDefaultsKey: UserDefaultsKeys.showTabKey,
                defaultValue: true
            ),
            ToggleSettingsItem(
                title: "Arrow Keys",
                accessibilityHint: "Include directional arrow keys",
                userDefaultsKey: UserDefaultsKeys.showArrowKeys,
                defaultValue: true
            ),
            ToggleSettingsItem(
                title: "Function Keys",
                accessibilityHint: "Include F1-F12 function keys",
                userDefaultsKey: UserDefaultsKeys.showFunctionKeys,
                defaultValue: false
            )
        ]
        
        return SettingsSection(
            title: "Special Keys",
            footer: "Add special keys for advanced MUD commands",
            items: items
        )
    }
} 