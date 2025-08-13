import UIKit

// MARK: - Settings Item Types

protocol SettingsItem {
    var title: String { get }
    var accessibilityLabel: String? { get }
    var accessibilityHint: String? { get }
}

struct SettingsSection {
    let title: String
    let footer: String?
    let items: [SettingsItem]
    
    init(title: String, footer: String? = nil, items: [SettingsItem]) {
        self.title = title
        self.footer = footer
        self.items = items
    }
}

struct ActionSettingsItem: SettingsItem {
    let title: String
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let action: () -> Void
    let style: UIAlertAction.Style
    
    init(title: String, accessibilityLabel: String? = nil, accessibilityHint: String? = nil, style: UIAlertAction.Style = .default, action: @escaping () -> Void) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
        self.style = style
    }
}

struct ToggleSettingsItem: SettingsItem {
    let title: String
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let userDefaultsKey: String
    let defaultValue: Bool
    let onToggle: ((Bool) -> Void)?
    
    init(title: String, accessibilityLabel: String? = nil, accessibilityHint: String? = nil, userDefaultsKey: String, defaultValue: Bool = false, onToggle: ((Bool) -> Void)? = nil) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.userDefaultsKey = userDefaultsKey
        self.defaultValue = defaultValue
        self.onToggle = onToggle
    }
    
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set { 
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            onToggle?(newValue)
        }
    }
}

struct NavigationSettingsItem: SettingsItem {
    let title: String
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let detail: String?
    let destination: () -> UIViewController
    
    init(title: String, detail: String? = nil, accessibilityLabel: String? = nil, accessibilityHint: String? = nil, destination: @escaping () -> UIViewController) {
        self.title = title
        self.detail = detail
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.destination = destination
    }
}

struct TextFieldSettingsItem: SettingsItem {
    let title: String
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let userDefaultsKey: String
    let placeholder: String?
    let perWorldKey: String? // when set, value is stored per-world via objectID.uriRepresentation().absoluteString
    let onChange: ((String) -> Void)?

    init(title: String, accessibilityLabel: String? = nil, accessibilityHint: String? = nil, userDefaultsKey: String, placeholder: String? = nil, perWorldKey: String? = nil, onChange: ((String) -> Void)? = nil) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.userDefaultsKey = userDefaultsKey
        self.placeholder = placeholder
        self.perWorldKey = perWorldKey
        self.onChange = onChange
    }
}

// MARK: - Base Settings View Controller

class SettingsViewController: UIViewController {
    
    // MARK: - Properties
    
    // Optional callback invoked after this controller is dismissed via Done
    var onDismiss: (() -> Void)?
    
    private var tableView: UITableView!
    private var sections: [SettingsSection] = []
    
    // MARK: - Initialization
    
    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSections()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
        tableView.reloadData()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        setupNavigationBar()
        setupTableView()
        setupConstraints()
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
    }
    
    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.separatorColor = .separator
        
        // Register cell types
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ActionCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ToggleCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "NavigationCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TextFieldCell")
        
        view.addSubview(tableView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func applyTheme() {
        // Use grouped system backgrounds for higher-contrast settings surfaces
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorColor = .separator
    }
    
    // MARK: - Configuration
    
    func setSections(_ sections: [SettingsSection]) {
        self.sections = sections
        if viewIfLoaded != nil {
            tableView.reloadData()
        }
    }
    
    // MARK: - Override Points
    
    /// Override this method to configure sections for the specific settings screen
    func setupSections() {
        // Base implementation - override in subclasses
    }
    
    // MARK: - Actions
    
    @objc private func doneButtonTapped() {
        let completion = onDismiss
        dismiss(animated: true) {
            completion?()
        }
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return sections[section].footer
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]
        
        switch item {
        case let actionItem as ActionSettingsItem:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
            configureActionCell(cell, with: actionItem)
            return cell
            
        case let toggleItem as ToggleSettingsItem:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ToggleCell", for: indexPath)
            configureToggleCell(cell, with: toggleItem)
            return cell
            
        case let navItem as NavigationSettingsItem:
            let cell = tableView.dequeueReusableCell(withIdentifier: "NavigationCell", for: indexPath)
            configureNavigationCell(cell, with: navItem)
            return cell
        case let textItem as TextFieldSettingsItem:
            let cell = tableView.dequeueReusableCell(withIdentifier: "TextFieldCell", for: indexPath)
            configureTextFieldCell(cell, with: textItem)
            return cell
            
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
            cell.textLabel?.text = item.title
            return cell
        }
    }
    
    private func configureActionCell(_ cell: UITableViewCell, with item: ActionSettingsItem) {
        cell.textLabel?.text = item.title
        cell.accessibilityLabel = item.accessibilityLabel ?? item.title
        cell.accessibilityHint = item.accessibilityHint
        cell.backgroundColor = .secondarySystemGroupedBackground
        
        switch item.style {
        case .destructive:
            cell.textLabel?.textColor = .systemRed
        default:
            cell.textLabel?.textColor = .label
        }
        
        cell.selectionStyle = .default
    }
    
    private func configureToggleCell(_ cell: UITableViewCell, with item: ToggleSettingsItem) {
        cell.textLabel?.text = item.title
        cell.accessibilityLabel = item.accessibilityLabel ?? item.title
        cell.accessibilityHint = item.accessibilityHint
        cell.selectionStyle = .none
        cell.backgroundColor = .secondarySystemGroupedBackground
        
        let toggle = UISwitch()
        toggle.isOn = item.isEnabled
        toggle.addTarget(self, action: #selector(toggleValueChanged(_:)), for: .valueChanged)
        toggle.tag = hash(item.userDefaultsKey) // Use hash for unique identification
        
        cell.accessoryView = toggle
    }
    
    private func configureNavigationCell(_ cell: UITableViewCell, with item: NavigationSettingsItem) {
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.detail
        cell.accessibilityLabel = item.accessibilityLabel ?? item.title
        cell.accessibilityHint = item.accessibilityHint ?? "Tap to open \(item.title)"
        cell.backgroundColor = .secondarySystemGroupedBackground
        
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
    }

    private func configureTextFieldCell(_ cell: UITableViewCell, with item: TextFieldSettingsItem) {
        cell.selectionStyle = .none
        cell.backgroundColor = .secondarySystemGroupedBackground
        cell.textLabel?.text = item.title
        cell.textLabel?.numberOfLines = 1
        let textField = UITextField(frame: .zero)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.textAlignment = .right
        textField.placeholder = item.placeholder
        textField.clearButtonMode = .whileEditing
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.accessibilityLabel = item.accessibilityLabel ?? item.title
        textField.accessibilityHint = item.accessibilityHint

        let key = item.userDefaultsKey
        if let worldScoped = item.perWorldKey {
            // per-world namespaced key will be set by caller when building item title; value loaded in SettingsHubVC
            textField.text = UserDefaults.standard.string(forKey: worldScoped) ?? ""
            textField.addAction(UIAction { _ in
                let value = textField.text ?? ""
                UserDefaults.standard.set(value, forKey: worldScoped)
                item.onChange?(value)
            }, for: .editingChanged)
        } else {
            textField.text = UserDefaults.standard.string(forKey: key) ?? ""
            textField.addAction(UIAction { _ in
                let value = textField.text ?? ""
                UserDefaults.standard.set(value, forKey: key)
                item.onChange?(value)
            }, for: .editingChanged)
        }

        cell.contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            textField.leadingAnchor.constraint(greaterThanOrEqualTo: cell.contentView.leadingAnchor, constant: 160)
        ])
    }
    
    @objc private func toggleValueChanged(_ sender: UISwitch) {
        // Find the toggle item by matching the hash
        for section in sections {
            for item in section.items {
                if let toggleItem = item as? ToggleSettingsItem,
                   hash(toggleItem.userDefaultsKey) == sender.tag {
                    // Update UserDefaults directly
                    UserDefaults.standard.set(sender.isOn, forKey: toggleItem.userDefaultsKey)
                    // Call the toggle callback
                    toggleItem.onToggle?(sender.isOn)
                    break
                }
            }
        }
    }
    
    private func hash(_ string: String) -> Int {
        return string.hashValue & 0x7FFFFFFF // Ensure positive hash
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let item = sections[indexPath.section].items[indexPath.row]
        
        switch item {
        case let actionItem as ActionSettingsItem:
            actionItem.action()
            
        case let navItem as NavigationSettingsItem:
            let destinationVC = navItem.destination()
            let navController = UINavigationController(rootViewController: destinationVC)
            navController.modalPresentationStyle = .pageSheet
            
            if #available(iOS 15.0, *) {
                if let sheet = navController.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
            }
            
            present(navController, animated: true)
            
        default:
            break
        }
    }
} 

// MARK: - Full-screen Settings Hub

// Duplicate SettingsHubViewController implementation moved to its own file.
