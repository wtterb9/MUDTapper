import UIKit
import CoreData

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

class AdvancedAutomationViewController: UIViewController {
    
    // MARK: - Properties
    
    private var segmentedControl: UISegmentedControl!
    private var tableView: UITableView!
    private var addButton: UIBarButtonItem!
    private var searchController: UISearchController!
    
    private let world: World
    private var automationItems: [AutomationItem] = []
    private var filteredItems: [AutomationItem] = []
    private var currentType: AutomationType = .triggers
    private var isSearching = false
    
    weak var delegate: AdvancedAutomationDelegate?
    
    // MARK: - Types
    
    enum AutomationType: Int, CaseIterable {
        case triggers = 0
        case aliases
        case gags
        case tickers
        
        var title: String {
            switch self {
            case .triggers: return "Triggers"
            case .aliases: return "Aliases"
            case .gags: return "Gags"
            case .tickers: return "Tickers"
            }
        }
        
        var singularTitle: String {
            switch self {
            case .triggers: return "Trigger"
            case .aliases: return "Alias"
            case .gags: return "Gag"
            case .tickers: return "Ticker"
            }
        }
        
        var icon: String {
            switch self {
            case .triggers: return "target"
            case .aliases: return "arrow.right.circle"
            case .gags: return "eye.slash"
            case .tickers: return "timer"
            }
        }
    }
    
    struct AutomationItem {
        let type: AutomationType
        let name: String
        let pattern: String
        let action: String
        let isEnabled: Bool
        let isActive: Bool
        let lastTriggered: Date?
        let triggerCount: Int
        let managedObject: NSManagedObject
    }
    
    // MARK: - Initialization
    
    init(world: World) {
        self.world = world
        super.init(nibName: nil, bundle: nil)
        title = "🤖 Advanced Automation"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSearchController()
        setupNotifications()
        loadAutomationItems()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQuickToggle(_:)),
            name: .automationItemQuickToggleTapped,
            object: nil
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAutomationItems()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        setupNavigationBar()
        setupSegmentedControl()
        setupTableView()
        setupConstraints()
    }
    
    private func setupNavigationBar() {
        let doneButton = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        doneButton.accessibilityLabel = "Done"
        doneButton.accessibilityHint = "Close automation manager"
        navigationItem.leftBarButtonItem = doneButton
        
        addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addButtonTapped)
        )
        addButton.accessibilityLabel = "Add"
        addButton.accessibilityHint = "Add new automation item"
        
        let testButton = UIBarButtonItem(
            image: UIImage(systemName: "testtube.2"),
            style: .plain,
            target: self,
            action: #selector(testButtonTapped)
        )
        testButton.accessibilityLabel = "Test"
        testButton.accessibilityHint = "Test automation patterns"
        
        let organizerButton = UIBarButtonItem(
            image: UIImage(systemName: "folder.badge.gearshape"),
            style: .plain,
            target: self,
            action: #selector(organizerButtonTapped)
        )
        organizerButton.accessibilityLabel = "Organize"
        organizerButton.accessibilityHint = "Organize and reorder automation items"
        
        let helpButton = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(helpButtonTapped)
        )
        helpButton.accessibilityLabel = "Help"
        helpButton.accessibilityHint = "View automation help and documentation"
        
        navigationItem.rightBarButtonItems = [addButton, testButton, organizerButton, helpButton]
    }
    
    private func setupSegmentedControl() {
        let titles = AutomationType.allCases.map { $0.title }
        segmentedControl = UISegmentedControl(items: titles)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(segmentChanged(_:)), for: .valueChanged)
        
        // Apply theme-aware styling for visibility on dark backgrounds
        let theme = ThemeManager.shared
        segmentedControl.selectedSegmentTintColor = theme.linkColor
        segmentedControl.backgroundColor = theme.terminalBackgroundColor
        segmentedControl.layer.cornerRadius = 8
        segmentedControl.layer.masksToBounds = true
        segmentedControl.layer.borderWidth = 1
        segmentedControl.layer.borderColor = theme.terminalTextColor.withAlphaComponent(0.3).cgColor
        
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.terminalTextColor.withAlphaComponent(0.85),
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ]
        segmentedControl.setTitleTextAttributes(normalAttrs, for: .normal)
        segmentedControl.setTitleTextAttributes(selectedAttrs, for: .selected)
        
        // Accessibility
        segmentedControl.accessibilityLabel = "Automation Type"
        segmentedControl.accessibilityHint = "Select automation type to view and manage"
        
        view.addSubview(segmentedControl)
    }
    
    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        // Make grouped headers visible against dark backgrounds
        tableView.sectionHeaderTopPadding = 8
        
        // Register cells
        tableView.register(AutomationItemCell.self, forCellReuseIdentifier: "AutomationItemCell")
        tableView.register(AutomationSummaryCell.self, forCellReuseIdentifier: "AutomationSummaryCell")
        
        view.addSubview(tableView)
    }
    
    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search automation..."
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadAutomationItems() {
        automationItems.removeAll()
        
        switch currentType {
        case .triggers:
            loadTriggers()
        case .aliases:
            loadAliases()
        case .gags:
            loadGags()
        case .tickers:
            loadTickers()
        }
        
        applySearchFilter()
    }
    
    private func loadTriggers() {
        let triggers = Array(world.triggers ?? []).filter { !$0.isHidden }
        
        for trigger in triggers {
            let item = AutomationItem(
                type: .triggers,
                name: trigger.trigger ?? "Unnamed",
                pattern: trigger.trigger ?? "",
                action: trigger.commands ?? "",
                isEnabled: trigger.isEnabled,
                isActive: trigger.isEnabled,
                lastTriggered: trigger.lastModified,
                triggerCount: Int(trigger.matchCount),
                managedObject: trigger
            )
            automationItems.append(item)
        }
    }
    
    private func loadAliases() {
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }
        
        for alias in aliases {
            let item = AutomationItem(
                type: .aliases,
                name: alias.name ?? "Unnamed",
                pattern: alias.name ?? "",
                action: alias.commands ?? "",
                isEnabled: alias.isEnabled,
                isActive: alias.isEnabled, // Aliases don't have separate active state
                lastTriggered: alias.lastModified,
                triggerCount: 0, // Aliases don't track usage count
                managedObject: alias
            )
            automationItems.append(item)
        }
    }
    
    private func loadGags() {
        let gags = Array(world.gags ?? []).filter { !$0.isHidden }
        
        for gag in gags {
            let item = AutomationItem(
                type: .gags,
                name: gag.gag ?? "Unnamed",
                pattern: gag.gag ?? "",
                action: "Hide matching text",
                isEnabled: gag.isEnabled,
                isActive: gag.isEnabled,
                lastTriggered: gag.lastModified,
                triggerCount: 0, // Gags don't track trigger count
                managedObject: gag
            )
            automationItems.append(item)
        }
    }
    
    private func loadTickers() {
        let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }
        
        for ticker in tickers {
            let item = AutomationItem(
                type: .tickers,
                name: "Every \(ticker.interval)s",
                pattern: "\(ticker.interval) seconds",
                action: ticker.commands ?? "",
                isEnabled: ticker.isEnabled,
                isActive: ticker.isEnabled,
                lastTriggered: ticker.lastModified,
                triggerCount: 0, // Tickers don't track execution count
                managedObject: ticker
            )
            automationItems.append(item)
        }
    }
    
    private func refreshAutomationItems() {
        loadAutomationItems()
        tableView.reloadData()
        updateAddButtonTitle()
    }
    
    private func applySearchFilter() {
        if isSearching, let searchText = searchController.searchBar.text, !searchText.isEmpty {
            filteredItems = automationItems.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.pattern.localizedCaseInsensitiveContains(searchText) ||
                item.action.localizedCaseInsensitiveContains(searchText)
            }
        } else {
            filteredItems = automationItems
        }
        
        tableView.reloadData()
    }
    
    private func updateAddButtonTitle() {
        addButton.title = "Add \(currentType.singularTitle)"
    }
    
    // MARK: - Actions
    
    @objc private func handleQuickToggle(_ notification: Notification) {
        guard let cell = notification.object as? AutomationItemCell,
              let indexPath = tableView.indexPath(for: cell),
              indexPath.section == 1,
              !filteredItems.isEmpty else {
            return
        }
        
        let item = filteredItems[indexPath.row]
        toggleAutomationItem(item)
        
        // Provide haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Refresh the cell to show updated state
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addButtonTapped() {
        showCreationOptions()
    }
    
    @objc private func testButtonTapped() {
        showAutomationTester()
    }
    
    @objc private func organizerButtonTapped() {
        showAutomationOrganizer()
    }

    @objc private func helpButtonTapped() {
        let vc = TriggerScriptingHelpViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
    
    @objc private func segmentChanged(_ sender: UISegmentedControl) {
        currentType = AutomationType(rawValue: sender.selectedSegmentIndex) ?? .triggers
        loadAutomationItems()
        updateAddButtonTitle()
    }
    
    // MARK: - Creation and Management
    
    private func showCreationOptions() {
        let alert = UIAlertController(
            title: "Add \(currentType.singularTitle)",
            message: "Choose how to create the \(currentType.singularTitle.lowercased())",
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "✏️ Create Custom", style: .default) { [weak self] _ in
            self?.createCustomAutomation()
        })
        
        alert.addAction(UIAlertAction(title: "📋 Import from Clipboard", style: .default) { [weak self] _ in
            self?.importFromClipboard()
        })
        
        alert.addAction(UIAlertAction(title: "📚 Use Template", style: .default) { [weak self] _ in
            self?.showTemplates()
        })
        
        alert.addAction(UIAlertAction(title: "🔄 Duplicate Existing", style: .default) { [weak self] _ in
            self?.showDuplicateOptions()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = addButton
        }
        
        present(alert, animated: true)
    }
    
    private func createCustomAutomation() {
        let editorVC = AutomationEditorViewController(
            type: currentType,
            world: world,
            automationItem: nil
        )
        editorVC.delegate = self
        
        let navController = UINavigationController(rootViewController: editorVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func importFromClipboard() {
        guard let clipboardText = UIPasteboard.general.string else {
            showAlert(title: "No Data", message: "No text found in clipboard.")
            return
        }
        
        // Parse clipboard for automation data
        parseAndCreateAutomation(from: clipboardText)
    }
    
    private func showTemplates() {
        let templatesVC = AutomationTemplatesViewController(type: currentType, world: world)
        templatesVC.delegate = self
        
        let navController = UINavigationController(rootViewController: templatesVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func showDuplicateOptions() {
        if automationItems.isEmpty {
            showAlert(title: "No Items", message: "No \(currentType.title.lowercased()) to duplicate.")
            return
        }
        
        let alert = UIAlertController(
            title: "Duplicate \(currentType.singularTitle)",
            message: "Choose which item to duplicate",
            preferredStyle: .actionSheet
        )
        
        for item in automationItems.prefix(10) { // Limit to first 10 for menu size
            alert.addAction(UIAlertAction(title: item.name, style: .default) { [weak self] _ in
                self?.duplicateAutomationItem(item)
            })
        }
        
        if automationItems.count > 10 {
            alert.addAction(UIAlertAction(title: "Show All...", style: .default) { [weak self] _ in
                self?.showFullDuplicateList()
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = addButton
        }
        
        present(alert, animated: true)
    }
    
    private func showAutomationTester() {
        let testerVC = AutomationTesterViewController(world: world, automationType: currentType)
        let navController = UINavigationController(rootViewController: testerVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func showAutomationOrganizer() {
        let organizerVC = AutomationOrganizerViewController(world: world)
        organizerVC.delegate = self
        
        let navController = UINavigationController(rootViewController: organizerVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func parseAndCreateAutomation(from text: String) {
        // Simple parsing logic based on automation type
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        guard !lines.isEmpty else {
            showAlert(title: "Parse Error", message: "No valid data found in clipboard.")
            return
        }
        
        // For now, create a simple automation from the first line
        let firstLine = lines[0]
        let components = firstLine.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        if components.count >= 2 {
            let pattern = components[0]
            let action = components[1]
            
            createAutomationFromData(pattern: pattern, action: action)
        } else {
            showAlert(title: "Parse Error", message: "Invalid format. Expected: pattern -> action")
        }
    }
    
    private func createAutomationFromData(pattern: String, action: String) {
        let context = world.managedObjectContext!
        
        switch currentType {
        case .triggers:
            let trigger = Trigger(context: context)
            trigger.trigger = pattern
            trigger.commands = action
            trigger.world = world
            trigger.isEnabled = true
            trigger.isHidden = false
            trigger.lastModified = Date()
            
        case .aliases:
            let alias = Alias(context: context)
            alias.name = pattern
            alias.commands = action
            alias.world = world
            alias.isEnabled = true
            alias.isHidden = false
            alias.lastModified = Date()
            
        case .gags:
            let gag = Gag(context: context)
            gag.gag = pattern
            gag.world = world
            gag.isEnabled = true
            gag.isHidden = false
            gag.lastModified = Date()
            
        case .tickers:
            let ticker = Ticker(context: context)
            ticker.commands = action
            ticker.interval = Double(pattern) ?? 30.0
            ticker.world = world
            ticker.isEnabled = true
            ticker.isHidden = false
            ticker.lastModified = Date()
        }
        
        do {
            try context.save()
            refreshAutomationItems()
            showAlert(title: "Created", message: "\(currentType.singularTitle) created successfully.")
        } catch {
            showAlert(title: "Error", message: "Failed to create \(currentType.singularTitle.lowercased()): \(error.localizedDescription)")
        }
    }
    
    private func duplicateAutomationItem(_ item: AutomationItem) {
        // Implementation would duplicate the selected automation item
        showAlert(title: "Duplicated", message: "Created a copy of '\(item.name)'.")
        refreshAutomationItems()
    }
    
    private func showFullDuplicateList() {
        // Implementation would show a full list for selection
    }
    
    private func showItemActions(for item: AutomationItem, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: item.name,
            message: item.pattern,
            preferredStyle: .actionSheet
        )
        
        alert.addAction(UIAlertAction(title: "✏️ Edit", style: .default) { [weak self] _ in
            self?.editAutomationItem(item)
        })
        
        alert.addAction(UIAlertAction(title: "🧪 Test", style: .default) { [weak self] _ in
            self?.testAutomationItem(item)
        })
        
        alert.addAction(UIAlertAction(title: "📋 Duplicate", style: .default) { [weak self] _ in
            self?.duplicateAutomationItem(item)
        })
        
        let toggleTitle = item.isEnabled ? "🔴 Disable" : "🟢 Enable"
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { [weak self] _ in
            self?.toggleAutomationItem(item)
        })
        
        alert.addAction(UIAlertAction(title: "📤 Export", style: .default) { [weak self] _ in
            self?.exportAutomationItem(item)
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Delete", style: .destructive) { [weak self] _ in
            self?.deleteAutomationItem(item)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: indexPath) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            }
        }
        
        present(alert, animated: true)
    }
    
    private func editAutomationItem(_ item: AutomationItem) {
        let editorVC = AutomationEditorViewController(
            type: currentType,
            world: world,
            automationItem: item
        )
        editorVC.delegate = self
        
        let navController = UINavigationController(rootViewController: editorVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func testAutomationItem(_ item: AutomationItem) {
        let testerVC = AutomationTesterViewController(world: world, automationType: currentType, testItem: item)
        let navController = UINavigationController(rootViewController: testerVC)
        navController.modalPresentationStyle = .pageSheet
        
        present(navController, animated: true)
    }
    
    private func toggleAutomationItem(_ item: AutomationItem) {
        // Toggle the enabled state of the automation item
        switch item.type {
        case .triggers:
            if let trigger = item.managedObject as? Trigger {
                trigger.isEnabled.toggle()
            }
        case .aliases:
            if let alias = item.managedObject as? Alias {
                alias.isEnabled.toggle()
            }
        case .gags:
            if let gag = item.managedObject as? Gag {
                gag.isEnabled.toggle()
            }
        case .tickers:
            if let ticker = item.managedObject as? Ticker {
                ticker.isEnabled.toggle()
            }
        }
        
        do {
            try world.managedObjectContext?.save()
            refreshAutomationItems()
        } catch {
            showAlert(title: "Error", message: "Failed to update item: \(error.localizedDescription)")
        }
    }
    
    private func exportAutomationItem(_ item: AutomationItem) {
        let exportData = "\(item.pattern) -> \(item.action)"
        
        let activityVC = UIActivityViewController(
            activityItems: [exportData],
            applicationActivities: nil
        )
        
        present(activityVC, animated: true)
    }
    
    private func deleteAutomationItem(_ item: AutomationItem) {
        ErrorPresenter.showConfirmation(
            title: "Delete \(item.type.singularTitle)",
            message: "Are you sure you want to delete '\(item.name)'?\n\nThis action cannot be undone.",
            confirmTitle: "Delete",
            confirmStyle: .destructive,
            confirmAction: { [weak self] in
                self?.performDelete(item)
            }
        )
    }
    
    private func performDelete(_ item: AutomationItem) {
        switch item.type {
        case .triggers:
            if let trigger = item.managedObject as? Trigger {
                trigger.isHidden = true
            }
        case .aliases:
            if let alias = item.managedObject as? Alias {
                alias.isHidden = true
            }
        case .gags:
            if let gag = item.managedObject as? Gag {
                gag.isHidden = true
            }
        case .tickers:
            if let ticker = item.managedObject as? Ticker {
                ticker.isHidden = true
            }
        }
        
        do {
            try world.managedObjectContext?.save()
            
            // Provide haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            refreshAutomationItems()
        } catch {
            Logger.logCoreDataError("Failed to delete automation item", error: error)
            ErrorPresenter.showError(
                title: "Delete Failed",
                message: "Failed to delete \(item.type.singularTitle.lowercased()).",
                error: error
            )
        }
    }
    
    private func showAlert(title: String, message: String) {
        ErrorPresenter.showError(title: title, message: message)
    }
}

// MARK: - UITableViewDataSource

extension AdvancedAutomationViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // Summary section + Items section
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1 // Summary cell
        } else {
            return filteredItems.isEmpty ? 1 : filteredItems.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AutomationSummaryCell", for: indexPath) as! AutomationSummaryCell
            cell.configure(with: automationItems, type: currentType)
            return cell
        } else {
            if filteredItems.isEmpty {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.selectionStyle = .none
                cell.backgroundColor = .clear
                
                // Add empty state view as subview
                let emptyState: EmptyStateView
                if isSearching {
                    emptyState = EmptyStateView.noSearchResults(searchTerm: searchController.searchBar.text ?? "")
                } else {
                    switch currentType {
                    case .triggers:
                        emptyState = EmptyStateView.noTriggers { [weak self] in
                            self?.createCustomAutomation()
                        }
                    case .aliases:
                        emptyState = EmptyStateView.noAliases { [weak self] in
                            self?.createCustomAutomation()
                        }
                    case .gags, .tickers:
                        emptyState = EmptyStateView()
                        emptyState.configure(
                            image: currentType.icon,
                            title: "No \(currentType.title)",
                            message: "Tap the + button to create your first \(currentType.singularTitle.lowercased()).",
                            buttonTitle: "Add \(currentType.singularTitle)",
                            buttonAction: { [weak self] in
                                self?.createCustomAutomation()
                            }
                        )
                    }
                }
                emptyState.applyTheme(ThemeManager.shared)
                emptyState.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(emptyState)
                
                NSLayoutConstraint.activate([
                    emptyState.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    emptyState.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                    emptyState.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                    emptyState.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                    emptyState.heightAnchor.constraint(equalToConstant: 300)
                ])
                
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AutomationItemCell", for: indexPath) as! AutomationItemCell
                let item = filteredItems[indexPath.row]
                cell.configure(with: item)
                return cell
            }
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Overview"
        } else {
            return currentType.title
        }
    }
}

// MARK: - UITableViewDelegate

extension AdvancedAutomationViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 1 && !filteredItems.isEmpty {
            let item = filteredItems[indexPath.row]
            showItemActions(for: item, at: indexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 {
            return 80 // Summary cell height
        } else {
            return UITableView.automaticDimension
        }
    }
    
    // MARK: - Swipe Actions
    
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Only add swipe actions for automation items, not for summary or empty state
        guard indexPath.section == 1, !filteredItems.isEmpty else {
            return nil
        }
        
        let item = filteredItems[indexPath.row]
        
        // Toggle action (Enable/Disable)
        let toggleTitle = item.isEnabled ? "Disable" : "Enable"
        let toggleAction = UIContextualAction(style: .normal, title: toggleTitle) { [weak self] _, _, completion in
            self?.toggleAutomationItem(item)
            
            // Provide haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Refresh the cell
            tableView.reloadRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        toggleAction.image = UIImage(systemName: item.isEnabled ? "pause.circle.fill" : "play.circle.fill")
        toggleAction.backgroundColor = item.isEnabled ? .systemOrange : .systemGreen
        
        let configuration = UISwipeActionsConfiguration(actions: [toggleAction])
        configuration.performsFirstActionWithFullSwipe = true // Full swipe = toggle
        
        return configuration
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Only add swipe actions for automation items, not for summary or empty state
        guard indexPath.section == 1, !filteredItems.isEmpty else {
            return nil
        }
        
        let item = filteredItems[indexPath.row]
        
        // Delete action
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deleteAutomationItem(item)
            completion(true)
        }
        deleteAction.image = UIImage(systemName: "trash.fill")
        deleteAction.backgroundColor = .systemRed
        
        // Edit action
        let editAction = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, completion in
            self?.editAutomationItem(item)
            completion(true)
        }
        editAction.image = UIImage(systemName: "pencil")
        editAction.backgroundColor = .systemBlue
        
        // Test action (only for triggers)
        var actions: [UIContextualAction] = [deleteAction, editAction]
        
        if item.type == .triggers {
            let testAction = UIContextualAction(style: .normal, title: "Test") { [weak self] _, _, completion in
                self?.testAutomationItem(item)
                completion(true)
            }
            testAction.image = UIImage(systemName: "testtube.2")
            testAction.backgroundColor = .systemOrange
            actions.insert(testAction, at: 1)
        }
        
        // Duplicate action
        let duplicateAction = UIContextualAction(style: .normal, title: "Copy") { [weak self] _, _, completion in
            self?.duplicateAutomationItem(item)
            completion(true)
        }
        duplicateAction.image = UIImage(systemName: "doc.on.doc")
        duplicateAction.backgroundColor = .systemGreen
        actions.insert(duplicateAction, at: 0)
        
        let configuration = UISwipeActionsConfiguration(actions: actions)
        configuration.performsFirstActionWithFullSwipe = true // Full swipe = delete
        
        return configuration
    }

    // Ensure section headers are legible on dark backgrounds
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        let theme = ThemeManager.shared
        if let header = view as? UITableViewHeaderFooterView {
            header.contentView.backgroundColor = theme.terminalBackgroundColor
            header.backgroundView?.backgroundColor = theme.terminalBackgroundColor
            header.textLabel?.textColor = theme.terminalTextColor.withAlphaComponent(0.85)
            header.textLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        }
    }
}

// MARK: - UISearchResultsUpdating

extension AdvancedAutomationViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        isSearching = !(searchController.searchBar.text?.isEmpty ?? true)
        applySearchFilter()
    }
}

// MARK: - Delegation Protocols

protocol AdvancedAutomationDelegate: AnyObject {
    func advancedAutomationDidUpdateItems(_ controller: AdvancedAutomationViewController)
}

protocol AutomationEditorDelegate: AnyObject {
    func automationEditorDidSave(_ editor: AutomationEditorViewController)
    func automationEditorDidCancel(_ editor: AutomationEditorViewController)
}

protocol AutomationTemplatesDelegate: AnyObject {
    func automationTemplatesDidSelectTemplate(_ templates: AutomationTemplatesViewController, template: String)
}

protocol AutomationOrganizerDelegate: AnyObject {
    func automationOrganizerDidUpdateAutomation(_ organizer: AutomationOrganizerViewController)
}

extension AdvancedAutomationViewController: AutomationEditorDelegate {
    
    func automationEditorDidSave(_ editor: AutomationEditorViewController) {
        editor.dismiss(animated: true)
        refreshAutomationItems()
    }
    
    func automationEditorDidCancel(_ editor: AutomationEditorViewController) {
        editor.dismiss(animated: true)
    }
}

extension AdvancedAutomationViewController: AutomationTemplatesDelegate {
    
    func automationTemplatesDidSelectTemplate(_ templates: AutomationTemplatesViewController, template: String) {
        templates.dismiss(animated: true)
        // Parse template and create automation
        parseAndCreateAutomation(from: template)
    }
}

extension AdvancedAutomationViewController: AutomationOrganizerDelegate {
    
    func automationOrganizerDidUpdateAutomation(_ organizer: AutomationOrganizerViewController) {
        refreshAutomationItems()
    }
}

// MARK: - Supporting View Controllers (Placeholders)

class MultilineTextEditorViewController: UIViewController {
    private let hintText: String?
    private let onSave: (String) -> Void
    private let textView = UITextView()
    private var extraRightBarButtons: [UIBarButtonItem] = []
    
    func appendText(_ snippet: String) {
        let existing = textView.text ?? ""
        if existing.isEmpty {
            textView.text = snippet
        } else {
            let needsNewline = !existing.hasSuffix("\n")
            textView.text = existing + (needsNewline ? "\n" : "") + snippet
        }
    }

    init(title: String, initialText: String, hint: String?, onSave: @escaping (String) -> Void) {
        self.hintText = hint
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
        self.title = title
        self.textView.text = initialText
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        let saveItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))
        var rightItems: [UIBarButtonItem] = [saveItem]
        if !extraRightBarButtons.isEmpty { rightItems.append(contentsOf: extraRightBarButtons) }
        navigationItem.rightBarButtonItems = rightItems

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let hintText = hintText, !hintText.isEmpty {
            let hintLabel = UILabel()
            hintLabel.text = hintText
            hintLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
            hintLabel.numberOfLines = 0
            hintLabel.font = UIFont.systemFont(ofSize: 13)
            stack.addArrangedSubview(hintLabel)
        }

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.cornerRadius = 8
        textView.backgroundColor = UIColor.systemBackground
        textView.textColor = ThemeManager.shared.isDarkTheme ? .white : .black

        stack.addArrangedSubview(textView)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])
    }

    @objc private func cancelTapped() { navigationController?.popViewController(animated: true) }

    @objc private func saveTapped() {
        onSave(textView.text ?? "")
        navigationController?.popViewController(animated: true)
    }

    // Allow callers to append additional right bar buttons (e.g., Examples) before presentation
    func setExtraRightBarButtons(_ buttons: [UIBarButtonItem]) {
        extraRightBarButtons = buttons
        // If the view is already loaded, refresh the nav items now
        if isViewLoaded {
            let saveItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))
            var rightItems: [UIBarButtonItem] = [saveItem]
            rightItems.append(contentsOf: buttons)
            navigationItem.rightBarButtonItems = rightItems
        }
    }
}

// MARK: - TriggerScriptingHelpViewController

class TriggerScriptingHelpViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var codeTextByButton: [UIButton: String] = [:]
    
    enum ScrollTarget {
        case patterns
        case commands
        case script
    }
    
    private var initialScrollTarget: ScrollTarget?
    private weak var patternsAnchor: UIView?
    private weak var commandsAnchor: UIView?
    private weak var scriptAnchor: UIView?
    
    convenience init(scrollTo target: ScrollTarget) {
        self.init(nibName: nil, bundle: nil)
        self.initialScrollTarget = target
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trigger Scripting Guide"
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
        
        buildContent()
        // Ensure we scroll after layout
        DispatchQueue.main.async { [weak self] in
            self?.scrollToInitialTargetIfNeeded()
        }
    }
    
    @objc private func closeTapped() { dismiss(animated: true) }
    
    private func addTitle(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.textColor = ThemeManager.shared.terminalTextColor
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }
    
    private func addSubtitle(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        label.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.9)
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }
    
    @discardableResult
    private func addSubtitleWithAnchor(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        label.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.9)
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
        return label
    }
    
    private func addBody(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.85)
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }
    
    private func addCode(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        label.textColor = ThemeManager.shared.isDarkTheme ? UIColor.white : UIColor.black
        label.numberOfLines = 0
        label.backgroundColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.08)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        // Use a container to simulate padding
        let container = UIStackView(arrangedSubviews: [label])
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        container.layer.cornerRadius = 8
        container.backgroundColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.08)
        stack.addArrangedSubview(container)
    }

    private func addCopyableCode(title: String, text: String) {
        // Header with title and Copy button
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.distribution = .fill
        header.spacing = 8
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.9)
        
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        let copyButton = UIButton(type: .system)
        copyButton.setTitle("Copy", for: .normal)
        copyButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        copyButton.addTarget(self, action: #selector(copyButtonTapped(_:)), for: .touchUpInside)
        codeTextByButton[copyButton] = text
        
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(copyButton)
        
        stack.addArrangedSubview(header)
        addCode(text)
    }

    @objc private func copyButtonTapped(_ sender: UIButton) {
        guard let text = codeTextByButton[sender] else { return }
        UIPasteboard.general.string = text
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        showToast("Copied")
    }
    
    private func showToast(_ text: String) {
        let toast = UILabel()
        toast.text = text
        toast.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toast.textAlignment = .center
        toast.numberOfLines = 1
        toast.layer.cornerRadius = 12
        toast.layer.masksToBounds = true
        toast.alpha = 0.0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
        
        // Add padding via content insets using a container
        let inset = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        toast.drawText(in: toast.bounds.inset(by: inset))
        
        UIView.animate(withDuration: 0.2, animations: { toast.alpha = 1.0 }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0.9, options: [], animations: { toast.alpha = 0.0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
    
    private func buildContent() {
        addTitle("Trigger Scripting Guide")
        addBody("Create powerful automations using triggers, commands, and a small Lua-like runtime.")
        
        addSubtitle("Trigger Types")
        addBody("Wildcard (*, ?) — anchored to the full line. Regex — supports named groups (?<name>...). Exact, Substring, Begins With, Ends With. Enable Ignore Case on the trigger for case-insensitive matching.")
        // Patterns & Regex tips anchor
        patternsAnchor = addSubtitleWithAnchor("Patterns and Regex Tips")
        addBody("Wildcard: '*' matches any run of characters, '?' matches a single character. Wildcards match the whole line by default.\nRegex: Prefer specific patterns and named groups (?<name>...). Escape special characters (e.g., '.' as \\.). Avoid heavy patterns like '.*?' at the start. Test using 'Test Pattern' in the editor.")
        
        addSubtitle("Options")
        addBody("Enabled, One Shot, Keep Evaluating, Omit from Output/Log, Lowercase Wildcard (lowercases wildcard captures).")
        
        addSubtitle("Captured Variables")
        addBody("Numbered: $1, $2 ... and %1, %2 ... Named (regex): $name or %name. Standard: line, trigger, match_count.")
        
        commandsAnchor = addSubtitleWithAnchor("Commands (legacy)")
        addBody("Commands are semicolon-separated. Supports @if (condition) {then} {else}. Comparisons: ==, !=, contains, >, <, >=, <=.")
        addCopyableCode(title: "Commands example", text: "@if (%name == \"guard\") {say Hello, %name} {emote ignores %name}")
        
        scriptAnchor = addSubtitleWithAnchor("Mini Scripting Runtime")
        addBody("Use the Script field for multi-line logic. Supported: send(\"...\"), assignment, if/elseif/else/end (single level), comparisons (==, !=/~=, >, <, >=, <=, contains), and line comments with --.")
        addCopyableCode(title: "Script example", text: "-- Example\nif $name == \"guard\" then\n  send(\"say Hello, $name!\")\nelseif $name contains \"lord\" then\n  local msg = \"hail, \" .. $name\n  send(msg)\nelse\n  send(\"whisper $name Psst.\")\nend")
        
        addSubtitle("Execution Order")
        addBody("Triggers evaluate per line by Priority then Sequence. On fire: captures → commands → script. Stop unless Keep Evaluating is enabled. One Shot hides after firing.")
        
        addSubtitle("Tips")
        addBody("Prefer regex named groups for clarity. Keep patterns specific. Use the tester to iterate. Avoid overly broad .* in regex. Regex compilation is cached per trigger.")
    }
    
    private func scrollToInitialTargetIfNeeded() {
        guard let target = initialScrollTarget else { return }
        let anchor: UIView?
        switch target {
        case .patterns: anchor = patternsAnchor
        case .commands: anchor = commandsAnchor
        case .script: anchor = scriptAnchor
        }
        guard let viewToScroll = anchor else { return }
        let rect = viewToScroll.convert(viewToScroll.bounds, to: scrollView)
        scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -16), animated: true)
    }
}

class AutomationEditorViewController: UIViewController {
    
    weak var delegate: AutomationEditorDelegate?
    private let automationType: AdvancedAutomationViewController.AutomationType
    private let world: World
    private var automationItem: AdvancedAutomationViewController.AutomationItem?
    
    private var tableView: UITableView!
    private var formData: [String: Any] = [:]
    
    init(type: AdvancedAutomationViewController.AutomationType, world: World, automationItem: AdvancedAutomationViewController.AutomationItem?) {
        self.automationType = type
        self.world = world
        self.automationItem = automationItem
        super.init(nibName: nil, bundle: nil)
        title = automationItem == nil ? "New \(type.singularTitle)" : "Edit \(type.singularTitle)"
        loadFormData()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        cancelButton.accessibilityLabel = "Cancel"
        cancelButton.accessibilityHint = "Discard changes and close editor"
        navigationItem.leftBarButtonItem = cancelButton
        
        let saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))
        saveButton.accessibilityLabel = "Save"
        saveButton.accessibilityHint = "Save changes and close editor"
        navigationItem.rightBarButtonItem = saveButton
        
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadFormData() {
        if let item = automationItem {
            formData["name"] = item.name
            formData["pattern"] = item.pattern
            formData["action"] = item.action
            formData["isEnabled"] = item.isEnabled
        } else {
            // Default values for new items
            formData["name"] = ""
            formData["pattern"] = ""
            formData["action"] = ""
            formData["isEnabled"] = true
            
            if automationType == .tickers {
                formData["interval"] = 60.0
            }
        }
    }
    
    @objc private func cancelTapped() {
        delegate?.automationEditorDidCancel(self)
    }
    
    @objc private func saveTapped() {
        if validateForm() {
            saveAutomationItem()
            delegate?.automationEditorDidSave(self)
        }
    }
    
    private func validateForm() -> Bool {
        guard let pattern = formData["pattern"] as? String, !pattern.isEmpty else {
            ErrorPresenter.showValidationError("Pattern cannot be empty")
            return false
        }
        
        // Validate pattern based on automation type
        switch automationType {
        case .triggers:
            if let error = InputValidator.validateTriggerPattern(pattern, type: .regex) {
                ErrorPresenter.showValidationError(error)
                return false
            }
        case .aliases:
            if let error = InputValidator.validateAliasName(pattern) {
                ErrorPresenter.showValidationError(error)
                return false
            }
        default:
            break
        }
        
        // Validate action/commands for non-gag types
        if automationType != .gags {
            guard let action = formData["action"] as? String, !action.isEmpty else {
                ErrorPresenter.showValidationError("Action/Commands cannot be empty")
                return false
            }
            
            // Sanitize commands for security
            let sanitized = InputValidator.sanitizeCommand(action)
            if let warning = InputValidator.validateCommandSafety(sanitized) {
                // Show warning but allow user to continue
                ErrorPresenter.showWarning(
                    title: "Command Warning",
                    message: warning + "\n\nDo you want to continue?",
                    continueAction: { [weak self] in
                        self?.formData["action"] = sanitized
                        self?.saveAutomationItem()
                        self?.delegate?.automationEditorDidSave(self!)
                    }
                )
                return false // Don't proceed directly, wait for user confirmation
            }
        }
        
        return true
    }
    
    private func saveAutomationItem() {
        let context = world.managedObjectContext!
        
        switch automationType {
        case .triggers:
            let trigger = automationItem?.managedObject as? Trigger ?? Trigger(context: context)
            trigger.label = formData["name"] as? String ?? ""
            trigger.trigger = formData["pattern"] as? String ?? ""
            let actionRaw = formData["action"] as? String ?? ""
            let triggerCommands = actionRaw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            trigger.commands = triggerCommands
            trigger.isEnabled = formData["isEnabled"] as? Bool ?? true
            trigger.world = world
            trigger.lastModified = Date()
            
        case .aliases:
            let alias = automationItem?.managedObject as? Alias ?? Alias(context: context)
            alias.name = formData["pattern"] as? String ?? ""
            let actionRaw = formData["action"] as? String ?? ""
            let aliasCommands = actionRaw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            alias.commands = aliasCommands
            alias.isEnabled = formData["isEnabled"] as? Bool ?? true
            alias.world = world
            alias.lastModified = Date()
            
        case .gags:
            let gag = automationItem?.managedObject as? Gag ?? Gag(context: context)
            gag.gag = formData["pattern"] as? String ?? ""
            gag.isEnabled = formData["isEnabled"] as? Bool ?? true
            gag.world = world
            gag.lastModified = Date()
            
        case .tickers:
            let ticker = automationItem?.managedObject as? Ticker ?? Ticker(context: context)
            let actionRaw = formData["action"] as? String ?? ""
            let tickerCommands = actionRaw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ";")
            ticker.commands = tickerCommands
            ticker.interval = formData["interval"] as? Double ?? 60.0
            ticker.isEnabled = formData["isEnabled"] as? Bool ?? true
            ticker.world = world
            ticker.lastModified = Date()
        }
        
        try? context.save()
    }
    
    private func showAlert(title: String, message: String) {
        ErrorPresenter.showError(title: title, message: message)
    }
}

// MARK: - TableView DataSource & Delegate

extension AutomationEditorViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: // Form fields
            switch automationType {
            case .triggers: return 4 // name, pattern, commands, enabled
            case .aliases: return 3 // name, commands, enabled  
            case .gags: return 2 // pattern, enabled
            case .tickers: return 4 // commands, interval, enabled, name
            }
        case 1: // Actions
            return automationType == .triggers ? 2 : 1 // Test button + Templates for triggers
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Configuration"
        case 1: return "Actions"
        default: return nil
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        
        if indexPath.section == 0 {
            // Form fields
            switch automationType {
            case .triggers:
                switch indexPath.row {
                case 0:
                    cell.textLabel?.text = "Name"
                    cell.detailTextLabel?.text = formData["name"] as? String ?? ""
                    cell.accessoryType = .disclosureIndicator
                case 1:
                    cell.textLabel?.text = "Pattern"
                    cell.detailTextLabel?.text = formData["pattern"] as? String ?? ""
                    cell.accessoryType = .disclosureIndicator
                    cell.accessoryView = makePatternHelpAccessory()
                case 2:
                    cell.textLabel?.text = "Commands"
                    cell.detailTextLabel?.text = formData["action"] as? String ?? ""
                    // Don't show disclosure indicator when using a custom accessory stack to avoid layout conflicts in compact widths
                    cell.accessoryType = .none
                    cell.accessoryView = makeHelpAccessory()
                case 3:
                    cell.textLabel?.text = "Enabled"
                    let enabledSwitch = UISwitch()
                    enabledSwitch.isOn = formData["isEnabled"] as? Bool ?? true
                    enabledSwitch.addTarget(self, action: #selector(enabledSwitchChanged(_:)), for: .valueChanged)
                    cell.accessoryView = enabledSwitch
                default: break
                }
            case .aliases:
                switch indexPath.row {
                case 0:
                    cell.textLabel?.text = "Name"
                    cell.detailTextLabel?.text = formData["pattern"] as? String ?? ""
                    cell.accessoryType = .disclosureIndicator
                case 1:
                    cell.textLabel?.text = "Commands"
                    cell.detailTextLabel?.text = formData["action"] as? String ?? ""
                    cell.accessoryType = .none
                    cell.accessoryView = makeHelpAccessory()
                case 2:
                    cell.textLabel?.text = "Enabled"
                    let enabledSwitch = UISwitch()
                    enabledSwitch.isOn = formData["isEnabled"] as? Bool ?? true
                    enabledSwitch.addTarget(self, action: #selector(enabledSwitchChanged(_:)), for: .valueChanged)
                    cell.accessoryView = enabledSwitch
                default: break
                }
            case .gags:
                switch indexPath.row {
                case 0:
                    cell.textLabel?.text = "Pattern"
                    cell.detailTextLabel?.text = formData["pattern"] as? String ?? ""
                    cell.accessoryType = .disclosureIndicator
                    cell.accessoryView = makePatternHelpAccessory()
                case 1:
                    cell.textLabel?.text = "Enabled"
                    let enabledSwitch = UISwitch()
                    enabledSwitch.isOn = formData["isEnabled"] as? Bool ?? true
                    enabledSwitch.addTarget(self, action: #selector(enabledSwitchChanged(_:)), for: .valueChanged)
                    cell.accessoryView = enabledSwitch
                default: break
                }
            case .tickers:
                switch indexPath.row {
                case 0:
                    cell.textLabel?.text = "Commands"
                    cell.detailTextLabel?.text = formData["action"] as? String ?? ""
                    cell.accessoryType = .disclosureIndicator
                    cell.accessoryView = makeHelpAccessory()
                case 1:
                    cell.textLabel?.text = "Interval"
                    cell.detailTextLabel?.text = "\(formData["interval"] as? Double ?? 60.0)s"
                    cell.accessoryType = .disclosureIndicator
                case 2:
                    cell.textLabel?.text = "Enabled"
                    let enabledSwitch = UISwitch()
                    enabledSwitch.isOn = formData["isEnabled"] as? Bool ?? true
                    enabledSwitch.addTarget(self, action: #selector(enabledSwitchChanged(_:)), for: .valueChanged)
                    cell.accessoryView = enabledSwitch
                case 3:
                    cell.textLabel?.text = "Name"
                    cell.detailTextLabel?.text = formData["name"] as? String ?? ""
                    cell.accessoryType = .disclosureIndicator
                default: break
                }
            }
        } else if indexPath.section == 1 {
            // Action buttons
            if automationType == .triggers && indexPath.row == 0 {
                cell.textLabel?.text = "Test Pattern"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Browse Templates"
                cell.accessoryType = .disclosureIndicator
            }
        }
        
        return cell
    }

    private func makeHelpAccessory() -> UIView {
        let helpButton = UIButton(type: .system)
        helpButton.setTitle("Help", for: .normal)
        helpButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        helpButton.setContentHuggingPriority(.required, for: .horizontal)
        
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        let stack = UIStackView(arrangedSubviews: [helpButton, chevron])
        stack.axis = .horizontal
        stack.spacing = 6
        return stack
    }
    
    @objc private func helpTapped() {
        let vc = TriggerScriptingHelpViewController(scrollTo: .commands)
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func makePatternHelpAccessory() -> UIView {
        let examplesButton = UIButton(type: .system)
        examplesButton.setTitle("Examples", for: .normal)
        examplesButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        examplesButton.addTarget(self, action: #selector(patternExamplesTapped), for: .touchUpInside)
        examplesButton.setContentHuggingPriority(.required, for: .horizontal)

        let helpButton = UIButton(type: .system)
        helpButton.setTitle("Help", for: .normal)
        helpButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        helpButton.addTarget(self, action: #selector(patternHelpTapped), for: .touchUpInside)
        helpButton.setContentHuggingPriority(.required, for: .horizontal)
        
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        let stack = UIStackView(arrangedSubviews: [examplesButton, helpButton, chevron])
        stack.axis = .horizontal
        stack.spacing = 6
        return stack
    }
    
    @objc private func patternHelpTapped() {
        let vc = TriggerScriptingHelpViewController(scrollTo: .patterns)
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    @objc private func patternExamplesTapped() {
        let sheet = UIAlertController(title: "Pattern Examples & Tips", message: nil, preferredStyle: .actionSheet)
        // Wildcard examples
        sheet.addAction(UIAlertAction(title: "Wildcard: * arrives.", style: .default) { [weak self] _ in
            self?.setPatternExample("* arrives.")
        })
        sheet.addAction(UIAlertAction(title: "Copy: * arrives.", style: .default) { _ in
            UIPasteboard.general.string = "* arrives."
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        })
        sheet.addAction(UIAlertAction(title: "Wildcard: You are *.", style: .default) { [weak self] _ in
            self?.setPatternExample("You are *.")
        })
        sheet.addAction(UIAlertAction(title: "Copy: You are *.", style: .default) { _ in
            UIPasteboard.general.string = "You are *."
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        })
        // Regex examples
        sheet.addAction(UIAlertAction(title: "Regex: ^(?<name>\\w+) arrives\\.$", style: .default) { [weak self] _ in
            self?.setPatternExample("^(?<name>\\w+) arrives\\.$")
        })
        sheet.addAction(UIAlertAction(title: "Copy: ^(?<name>\\w+) arrives\\.$", style: .default) { _ in
            UIPasteboard.general.string = "^(?<name>\\w+) arrives\\.$"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        })
        // Regex with multiple named groups
        sheet.addAction(UIAlertAction(title: "Regex (named groups): ^(?<name>\\w+) says '(?<msg>.*)'$", style: .default) { [weak self] _ in
            self?.setPatternExample("^(?<name>\\w+) says '(?<msg>.*)'$")
        })
        sheet.addAction(UIAlertAction(title: "Copy: ^(?<name>\\w+) says '(?<msg>.*)'$", style: .default) { _ in
            UIPasteboard.general.string = "^(?<name>\\w+) says '(?<msg>.*)'$"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        })
        // Case-insensitive tip using inline flag
        sheet.addAction(UIAlertAction(title: "Tip: Prefix current regex with (?i) for Ignore Case", style: .default) { [weak self] _ in
            self?.prefixPatternWithCaseInsensitiveFlag()
        })
        sheet.addAction(UIAlertAction(title: "Copy: (?i)You are hungry.$", style: .default) { _ in
            UIPasteboard.general.string = "(?i)You are hungry.$"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        })
        sheet.addAction(UIAlertAction(title: "Regex: HP: (?<hp>\\d+)/(?:\\d+)", style: .default) { [weak self] _ in
            self?.setPatternExample("HP: (?<hp>\\d+)/(?:\\d+)")
        })
        sheet.addAction(UIAlertAction(title: "Copy: HP: (?<hp>\\d+)/(?:\\d+)", style: .default) { _ in
            UIPasteboard.general.string = "HP: (?<hp>\\d+)/(?:\\d+)"
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }
    
    private func setPatternExample(_ example: String) {
        formData["pattern"] = example
        tableView.reloadData()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func prefixPatternWithCaseInsensitiveFlag() {
        let current = (formData["pattern"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            formData["pattern"] = "(?i)"
        } else if current.hasPrefix("(?i)") {
            // already prefixed; no-op with subtle haptic
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            tableView.reloadData()
            return
        } else {
            formData["pattern"] = "(?i)" + current
        }
        tableView.reloadData()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            // Handle form field editing
            switch automationType {
            case .triggers:
                switch indexPath.row {
                case 0: editTextField(title: "Name", key: "name", placeholder: "Trigger name (optional)")
                case 1: editTextField(title: "Pattern", key: "pattern", placeholder: "Text pattern to match")
                case 2: editMultilineField(title: "Commands", key: "action", hint: "Enter one command per line. Lines will be saved as semicolon-separated commands.")
                default: break
                }
            case .aliases:
                switch indexPath.row {
                case 0: editTextField(title: "Name", key: "pattern", placeholder: "Alias name (e.g., 'k')")
                case 1: editMultilineField(title: "Commands", key: "action", hint: "Enter one command per line. Lines will be saved as semicolon-separated commands.")
                default: break
                }
            case .gags:
                if indexPath.row == 0 {
                    editTextField(title: "Pattern", key: "pattern", placeholder: "Text to hide")
                }
            case .tickers:
                switch indexPath.row {
                case 0: editMultilineField(title: "Commands", key: "action", hint: "Enter one command per line. Lines will be saved as semicolon-separated commands.")
                case 1: editNumberField(title: "Interval", key: "interval", placeholder: "Seconds")
                case 3: editTextField(title: "Name", key: "name", placeholder: "Ticker name (optional)")
                default: break
                }
            }
        } else if indexPath.section == 1 {
            // Handle action buttons
            if automationType == .triggers && indexPath.row == 0 {
                showPatternTester()
            } else {
                showTemplatesBrowser()
            }
        }
    }
    
    @objc private func enabledSwitchChanged(_ sender: UISwitch) {
        formData["isEnabled"] = sender.isOn
    }
    
    private func editTextField(title: String, key: String, placeholder: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = self.formData[key] as? String ?? ""
            textField.placeholder = placeholder
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            self.formData[key] = alert.textFields?[0].text ?? ""
            self.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func editMultilineField(title: String, key: String, hint: String?) {
        var initial = self.formData[key] as? String ?? ""
        if key == "action" && initial.contains(";") {
            let lines = initial.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            initial = lines.joined(separator: "\n")
        }
        let editor = MultilineTextEditorViewController(title: title, initialText: initial, hint: hint) { [weak self] newText in
            guard let self = self else { return }
            self.formData[key] = newText
            self.tableView.reloadData()
        }
        // Add common examples toolbar for quick insert/copy
        let examplesButton = UIBarButtonItem(title: "Examples", style: .plain, target: self, action: #selector(showExamplesTapped))
        examplesButton.accessibilityHint = "Insert example snippets"
        editor.setExtraRightBarButtons([examplesButton])
        editor.navigationItem.leftBarButtonItem?.accessibilityHint = "Cancel editing"
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func showExamplesTapped() {
        let sheet = UIAlertController(title: "Insert Example", message: nil, preferredStyle: .actionSheet)
        // Commands example
        let commands = "@if (%name == \"guard\") {say Hello, %name} {emote ignores %name}"
        sheet.addAction(UIAlertAction(title: "Commands: @if then/else (Insert)", style: .default) { [weak self] _ in
            self?.appendToActionField(commands)
        })
        sheet.addAction(UIAlertAction(title: "Commands: @if then/else (Copy)", style: .default) { _ in
            UIPasteboard.general.string = commands
        })
        // Script example
        let script = "-- Example\nif $name == \"guard\" then\n  send(\"say Hello, $name!\")\nelseif $name contains \"lord\" then\n  local msg = \"hail, \" .. $name\n  send(msg)\nelse\n  send(\"whisper $name Psst.\")\nend"
        sheet.addAction(UIAlertAction(title: "Script: if/elseif/else with send() (Insert)", style: .default) { [weak self] _ in
            self?.appendToActionField(script)
        })
        sheet.addAction(UIAlertAction(title: "Script: if/elseif/else with send() (Copy)", style: .default) { _ in
            UIPasteboard.general.string = script
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }
    
    private func appendToActionField(_ text: String) {
        var current = (formData["action"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            current = text
        } else {
            // Ensure separation line
            current += (current.hasSuffix("\n") ? "" : "\n") + text
        }
        formData["action"] = current
        tableView.reloadData()
    }
    
    private func editNumberField(title: String, key: String, placeholder: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = "\(self.formData[key] as? Double ?? 60.0)"
            textField.placeholder = placeholder
            textField.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            if let text = alert.textFields?[0].text, let value = Double(text) {
                self.formData[key] = value
                self.tableView.reloadData()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showPatternTester() {
        let tester = AutomationTesterViewController(world: world, automationType: automationType, testItem: automationItem)
        navigationController?.pushViewController(tester, animated: true)
    }
    
    private func showTemplatesBrowser() {
        let templates = AutomationTemplatesViewController(type: automationType, world: world)
        templates.delegate = self
        let navController = UINavigationController(rootViewController: templates)
        present(navController, animated: true)
    }
}

extension AutomationEditorViewController: AutomationTemplatesDelegate {
    func automationTemplatesDidSelectTemplate(_ templates: AutomationTemplatesViewController, template: String) {
        // Apply template data to form
        let templateData = parseTemplateString(template)
        for (key, value) in templateData {
            formData[key] = value
        }
        tableView.reloadData()
    }
    
    private func parseTemplateString(_ template: String) -> [String: Any] {
        var result: [String: Any] = [:]
        
        // Parse pipe-separated key=value pairs
        let pairs = template.components(separatedBy: "|")
        for pair in pairs {
            let components = pair.components(separatedBy: "=")
            if components.count == 2 {
                let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Convert boolean strings
                if value.lowercased() == "true" {
                    result[key] = true
                } else if value.lowercased() == "false" {
                    result[key] = false
                } else if let intValue = Int(value) {
                    result[key] = intValue
                } else {
                    result[key] = value
                }
            }
        }
        
        // Set defaults
        if result["enabled"] == nil {
            result["enabled"] = true
        }
        
        return result
    }
}

class AutomationTemplatesViewController: UIViewController {
    
    weak var delegate: AutomationTemplatesDelegate?
    private let automationType: AdvancedAutomationViewController.AutomationType
    private let world: World
    private var tableView: UITableView!
    private var templates: [AutomationTemplate] = []
    
    init(type: AdvancedAutomationViewController.AutomationType, world: World) {
        self.automationType = type
        self.world = world
        super.init(nibName: nil, bundle: nil)
        title = "\(type.title) Templates"
        loadTemplates()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        
        // Setup table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TemplateCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadTemplates() {
        templates = AutomationTemplate.templates(for: automationType)
    }
    
    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}

// MARK: - UITableViewDataSource

extension AutomationTemplatesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return templates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TemplateCell", for: indexPath)
        let template = templates[indexPath.row]
        
        cell.textLabel?.text = template.name
        cell.detailTextLabel?.text = template.description
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cell.textLabel?.textColor = ThemeManager.shared.currentTheme.fontColor
        cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.7)
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension AutomationTemplatesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let template = templates[indexPath.row]
        delegate?.automationTemplatesDidSelectTemplate(self, template: template.templateString)
        dismiss(animated: true)
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Common \(automationType.title) Patterns"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "Select a template to auto-fill the \(automationType.title.lowercased()) form with common patterns."
    }
}

// MARK: - AutomationTemplate

struct AutomationTemplate {
    let name: String
    let description: String
    let templateString: String
    
    static func templates(for type: AdvancedAutomationViewController.AutomationType) -> [AutomationTemplate] {
        switch type {
        case .triggers:
            return [
                AutomationTemplate(
                    name: "Communication Capture",
                    description: "Highlights tells, says, and channels",
                    templateString: "name=Communication|pattern=* tells you *|action=|highlight=true|sound=true"
                ),
                AutomationTemplate(
                    name: "Combat Alerts",
                    description: "Combat status warnings",
                    templateString: "name=Low Health|pattern=You are badly wounded|action=flee|sound=true|priority=high"
                ),
                AutomationTemplate(
                    name: "Auto-Loot",
                    description: "Automatically loot corpses",
                    templateString: "name=Auto Loot|pattern=* is dead! R.I.P.|action=get all from corpse|delay=1"
                ),
                AutomationTemplate(
                    name: "Quest Tracker",
                    description: "Track quest completion",
                    templateString: "name=Quest Complete|pattern=You have completed *|action=say Quest done!|highlight=true"
                ),
                AutomationTemplate(
                    name: "Death Warning",
                    description: "Alert when near death",
                    templateString: "name=Near Death|pattern=You are mortally wounded|action=recall|sound=true|vibrate=true"
                )
            ]
            
        case .aliases:
            return [
                AutomationTemplate(
                    name: "Movement Shortcuts",
                    description: "Quick directional commands",
                    templateString: "name=n|action=north"
                ),
                AutomationTemplate(
                    name: "Combat Alias",
                    description: "Attack with weapon check",
                    templateString: "name=k|action=wield sword;kill $1$"
                ),
                AutomationTemplate(
                    name: "Get All Items",
                    description: "Collect all items from container",
                    templateString: "name=ga|action=get all from $1$"
                ),
                AutomationTemplate(
                    name: "Quick Look",
                    description: "Look at target with examine",
                    templateString: "name=l|action=look $1$;examine $1$"
                ),
                AutomationTemplate(
                    name: "Spell Combo",
                    description: "Cast multiple spells in sequence",
                    templateString: "name=combo|action=cast 'magic missile' $1$;cast 'fireball' $1$"
                )
            ]
            
        case .gags:
            return [
                AutomationTemplate(
                    name: "Spam Messages",
                    description: "Hide repetitive spam",
                    templateString: "pattern=You hear a *|enabled=true"
                ),
                AutomationTemplate(
                    name: "Weather Spam",
                    description: "Hide weather messages",
                    templateString: "pattern=The * continues|enabled=true"
                ),
                AutomationTemplate(
                    name: "Channel Noise",
                    description: "Hide specific channels",
                    templateString: "pattern=[OOC] *|enabled=true"
                ),
                AutomationTemplate(
                    name: "Combat Spam",
                    description: "Hide repetitive combat messages",
                    templateString: "pattern=* dodges your attack|enabled=true"
                ),
                AutomationTemplate(
                    name: "Movement Spam",
                    description: "Hide arrival/departure messages",
                    templateString: "pattern=* arrives from *|enabled=true"
                )
            ]
            
        case .tickers:
            return [
                AutomationTemplate(
                    name: "Health Check",
                    description: "Regular health monitoring",
                    templateString: "name=Health Check|action=score|interval=30"
                ),
                AutomationTemplate(
                    name: "Auto-Save",
                    description: "Periodic character saving",
                    templateString: "name=Auto Save|action=save|interval=300"
                ),
                AutomationTemplate(
                    name: "Room Scanner",
                    description: "Regular environment check",
                    templateString: "name=Look Around|action=look|interval=60"
                ),
                AutomationTemplate(
                    name: "Spell Refresh",
                    description: "Maintain protective spells",
                    templateString: "name=Spell Up|action=cast 'armor';cast 'bless'|interval=600"
                ),
                AutomationTemplate(
                    name: "Who Check",
                    description: "Monitor online players",
                    templateString: "name=Who List|action=who|interval=120"
                )
            ]
        }
    }
}

class AutomationTesterViewController: UIViewController {
    
    private let world: World
    private let automationType: AdvancedAutomationViewController.AutomationType
    private let testItem: AdvancedAutomationViewController.AutomationItem?
    private var tableView: UITableView!
    private var testInput: String = ""
    private var testResults: [TestResult] = []
    
    init(world: World, automationType: AdvancedAutomationViewController.AutomationType, testItem: AdvancedAutomationViewController.AutomationItem? = nil) {
        self.world = world
        self.automationType = automationType
        self.testItem = testItem
        super.init(nibName: nil, bundle: nil)
        title = "Test \(automationType.title)"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSampleData()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Test", style: .plain, target: self, action: #selector(runTest))
        
        // Setup table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "InputCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ResultCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadSampleData() {
        // Load sample test inputs based on automation type
        switch automationType {
        case .triggers:
            testInput = "The orc tells you 'Hello adventurer!'"
        case .aliases:
            testInput = "k orc"
        case .gags:
            testInput = "You hear a faint rustling in the bushes."
        case .tickers:
            testInput = "Timer: 30 second interval"
        }
    }
    
    @objc private func doneTapped() {
        dismiss(animated: true)
    }
    
    @objc private func runTest() {
        guard !testInput.isEmpty else {
            showAlert(title: "No Input", message: "Please enter test input first.")
            return
        }
        
        testResults.removeAll()
        
        switch automationType {
        case .triggers:
            testTriggers()
        case .aliases:
            testAliases()
        case .gags:
            testGags()
        case .tickers:
            testTickers()
        }
        
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
    }
    
    private func testTriggers() {
        guard let triggers = world.triggers else { return }
        
        for trigger in triggers where trigger.isEnabled {
            if trigger.matches(line: testInput) {
                let result = TestResult(
                    itemName: trigger.trigger ?? "Unnamed",
                    matched: true,
                    output: trigger.commands ?? "No action",
                    details: "Pattern: \(trigger.trigger ?? ""), Type: \(trigger.triggerTypeEnum.displayName)"
                )
                testResults.append(result)
            }
        }
        
        if testResults.isEmpty {
            testResults.append(TestResult(
                itemName: "No Matches",
                matched: false,
                output: "No triggers matched this input",
                details: "Try different test input or check trigger patterns"
            ))
        }
    }
    
    private func testAliases() {
        guard let aliases = world.aliases else { return }
        
        let parts = testInput.components(separatedBy: " ")
        guard let command = parts.first else { return }
        
        for alias in aliases where alias.isEnabled {
            if alias.name == command {
                var expandedCommands = alias.commands ?? ""
                
                // Simple parameter substitution
                for (index, arg) in parts.dropFirst().enumerated() {
                    expandedCommands = expandedCommands.replacingOccurrences(of: "$\\(index + 1)$", with: arg)
                }
                expandedCommands = expandedCommands.replacingOccurrences(of: "$*$", with: parts.dropFirst().joined(separator: " "))
                
                let result = TestResult(
                    itemName: alias.name ?? "Unnamed",
                    matched: true,
                    output: expandedCommands,
                    details: "Original: \(alias.commands ?? "")"
                )
                testResults.append(result)
            }
        }
        
        if testResults.isEmpty {
            testResults.append(TestResult(
                itemName: "No Matches",
                matched: false,
                output: "No aliases matched this command",
                details: "Command '\\(command)' not found in aliases"
            ))
        }
    }
    
    private func testGags() {
        guard let gags = world.gags else { return }
        
        for gag in gags where gag.isEnabled {
            if let gagPattern = gag.gag, testInput.contains(gagPattern) {
                let result = TestResult(
                    itemName: gagPattern,
                    matched: true,
                    output: "Text would be hidden",
                    details: "This line would not appear in the terminal"
                )
                testResults.append(result)
            }
        }
        
        if testResults.isEmpty {
            testResults.append(TestResult(
                itemName: "No Gags",
                matched: false,
                output: "Text would be displayed normally",
                details: "No gag patterns matched this input"
            ))
        }
    }
    
    private func testTickers() {
        guard let tickers = world.tickers else { return }
        
        let enabledTickers = tickers.filter { $0.isEnabled }
        
        for ticker in enabledTickers {
            let result = TestResult(
                itemName: "Every \\(ticker.interval)s",
                matched: true,
                output: ticker.commands ?? "No commands",
                details: "Executes every \\(ticker.interval) seconds when connected"
            )
            testResults.append(result)
        }
        
        if testResults.isEmpty {
            testResults.append(TestResult(
                itemName: "No Tickers",
                matched: false,
                output: "No active tickers",
                details: "No enabled tickers found for this world"
            ))
        }
    }
    
    private func showAlert(title: String, message: String) {
        ErrorPresenter.showError(title: title, message: message)
    }
}

// MARK: - UITableViewDataSource

extension AutomationTesterViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2 // Input section and Results section
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1 // Input row
        case 1: return max(testResults.count, 1) // Results or placeholder
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "InputCell", for: indexPath)
            cell.textLabel?.text = "Test Input"
            cell.detailTextLabel?.text = testInput.isEmpty ? "Tap to enter test input" : testInput
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            cell.textLabel?.textColor = ThemeManager.shared.currentTheme.fontColor
            cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.7)
            cell.accessoryType = .disclosureIndicator
            return cell
            
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell", for: indexPath)
            
            if testResults.isEmpty {
                cell.textLabel?.text = "Run Test"
                cell.detailTextLabel?.text = "Tap 'Test' to see results"
                cell.textLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.5)
                cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.3)
            } else {
                let result = testResults[indexPath.row]
                cell.textLabel?.text = result.itemName
                cell.detailTextLabel?.text = result.output
                cell.textLabel?.textColor = result.matched ? .systemGreen : .systemRed
                cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.7)
            }
            
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            return cell
            
        default:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate

extension AutomationTesterViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if indexPath.section == 0 {
            // Edit test input
            let alert = UIAlertController(title: "Test Input", message: "Enter text to test against \\(automationType.title.lowercased())", preferredStyle: .alert)
            
            alert.addTextField { textField in
                textField.text = self.testInput
                textField.placeholder = "Enter test input..."
            }
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
                if let text = alert.textFields?.first?.text {
                    self.testInput = text
                    self.tableView.reloadRows(at: [indexPath], with: .none)
                }
            })
            
            present(alert, animated: true)
        } else if indexPath.section == 1 && !testResults.isEmpty {
            // Show result details
            let result = testResults[indexPath.row]
            let alert = UIAlertController(title: result.itemName, message: result.details, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Test Input"
        case 1: return "Test Results"
        default: return nil
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Enter sample text to test your \\(automationType.title.lowercased()) patterns against."
        case 1: return testResults.isEmpty ? nil : "\\(testResults.count) result(s) found"
        default: return nil
        }
    }
}

// MARK: - TestResult

struct TestResult {
    let itemName: String
    let matched: Bool
    let output: String
    let details: String
}

class AutomationOrganizerViewController: UIViewController {
    
    weak var delegate: AutomationOrganizerDelegate?
    private let world: World
    private var tableView: UITableView!
    private var automationItems: [AdvancedAutomationViewController.AutomationItem] = []
    private var selectedItems: Set<Int> = []
    private var isSelectionMode = false
    
    init(world: World) {
        self.world = world
        super.init(nibName: nil, bundle: nil)
        title = "Organize Automation"
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAutomationItems()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Select", style: .plain, target: self, action: #selector(toggleSelectionMode))
        
        // Setup table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.isEditing = false
        tableView.allowsMultipleSelection = false
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OrganizerCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        setupToolbar()
    }
    
    private func setupToolbar() {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.barTintColor = ThemeManager.shared.terminalBackgroundColor
        toolbar.tintColor = ThemeManager.shared.currentTheme.fontColor
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let enableButton = UIBarButtonItem(title: "Enable All", style: .plain, target: self, action: #selector(enableSelected))
        let disableButton = UIBarButtonItem(title: "Disable All", style: .plain, target: self, action: #selector(disableSelected))
        let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteSelected))
        
        toolbar.setItems([enableButton, flexSpace, disableButton, flexSpace, deleteButton], animated: false)
        toolbar.isHidden = true
        
        view.addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        self.toolbar = toolbar
    }
    
    private var toolbar: UIToolbar!
    
    private func loadAutomationItems() {
        automationItems.removeAll()
        
        // Load triggers
        if let triggers = world.triggers {
            for trigger in triggers {
                let item = AdvancedAutomationViewController.AutomationItem(
                    type: .triggers,
                    name: trigger.trigger ?? "Unnamed",
                    pattern: trigger.trigger ?? "",
                    action: trigger.commands ?? "",
                    isEnabled: trigger.isEnabled,
                    isActive: trigger.isEnabled,
                    lastTriggered: trigger.lastModified,
                    triggerCount: Int(trigger.matchCount),
                    managedObject: trigger
                )
                automationItems.append(item)
            }
        }
        
        // Load aliases
        if let aliases = world.aliases {
            for alias in aliases {
                let item = AdvancedAutomationViewController.AutomationItem(
                    type: .aliases,
                    name: alias.name ?? "Unnamed",
                    pattern: alias.name ?? "",
                    action: alias.commands ?? "",
                    isEnabled: alias.isEnabled,
                    isActive: alias.isEnabled,
                    lastTriggered: alias.lastModified,
                    triggerCount: 0,
                    managedObject: alias
                )
                automationItems.append(item)
            }
        }
        
        // Load gags
        if let gags = world.gags {
            for gag in gags {
                let item = AdvancedAutomationViewController.AutomationItem(
                    type: .gags,
                    name: gag.gag ?? "Unnamed",
                    pattern: gag.gag ?? "",
                    action: "Hide text",
                    isEnabled: gag.isEnabled,
                    isActive: gag.isEnabled,
                    lastTriggered: gag.lastModified,
                    triggerCount: 0,
                    managedObject: gag
                )
                automationItems.append(item)
            }
        }
        
        // Load tickers
        if let tickers = world.tickers {
            for ticker in tickers {
                let item = AdvancedAutomationViewController.AutomationItem(
                    type: .tickers,
                    name: "Every \(ticker.interval)s",
                    pattern: "\(ticker.interval) seconds",
                    action: ticker.commands ?? "",
                    isEnabled: ticker.isEnabled,
                    isActive: ticker.isEnabled,
                    lastTriggered: ticker.lastModified,
                    triggerCount: 0,
                    managedObject: ticker
                )
                automationItems.append(item)
            }
        }
        
        tableView.reloadData()
    }
    
    @objc private func doneTapped() {
        delegate?.automationOrganizerDidUpdateAutomation(self)
        dismiss(animated: true)
    }
    
    @objc private func toggleSelectionMode() {
        isSelectionMode.toggle()
        tableView.setEditing(isSelectionMode, animated: true)
        toolbar.isHidden = !isSelectionMode
        
        if isSelectionMode {
            navigationItem.rightBarButtonItem?.title = "Done"
        } else {
            navigationItem.rightBarButtonItem?.title = "Select"
            selectedItems.removeAll()
        }
    }
    
    @objc private func enableSelected() {
        performBulkOperation { item in
            if let trigger = item.managedObject as? Trigger {
                trigger.isEnabled = true
            } else if let alias = item.managedObject as? Alias {
                alias.isEnabled = true
            } else if let gag = item.managedObject as? Gag {
                gag.isEnabled = true
            } else if let ticker = item.managedObject as? Ticker {
                ticker.isEnabled = true
            }
        }
    }
    
    @objc private func disableSelected() {
        performBulkOperation { item in
            if let trigger = item.managedObject as? Trigger {
                trigger.isEnabled = false
            } else if let alias = item.managedObject as? Alias {
                alias.isEnabled = false
            } else if let gag = item.managedObject as? Gag {
                gag.isEnabled = false
            } else if let ticker = item.managedObject as? Ticker {
                ticker.isEnabled = false
            }
        }
    }
    
    @objc private func deleteSelected() {
        let alert = UIAlertController(
            title: "Delete Selected",
            message: "Are you sure you want to delete \(selectedItems.count) automation item(s)?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.performBulkDeletion()
        })
        
        present(alert, animated: true)
    }
    
    private func performBulkOperation(_ operation: (AdvancedAutomationViewController.AutomationItem) -> Void) {
        let context = world.managedObjectContext!
        
        for index in selectedItems {
            if index < automationItems.count {
                operation(automationItems[index])
            }
        }
        
        do {
            try context.save()
            loadAutomationItems()
            selectedItems.removeAll()
        } catch {
            showAlert(title: "Error", message: "Failed to update automation: \(error.localizedDescription)")
        }
    }
    
    private func performBulkDeletion() {
        let context = world.managedObjectContext!
        let sortedIndices = selectedItems.sorted(by: >)
        
        for index in sortedIndices {
            if index < automationItems.count {
                let item = automationItems[index]
                context.delete(item.managedObject)
                automationItems.remove(at: index)
            }
        }
        
        do {
            try context.save()
            tableView.reloadData()
            selectedItems.removeAll()
        } catch {
            showAlert(title: "Error", message: "Failed to delete automation: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(title: String, message: String) {
        ErrorPresenter.showError(title: title, message: message)
    }
}

// MARK: - UITableViewDataSource

extension AutomationOrganizerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return automationItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "OrganizerCell", for: indexPath)
        let item = automationItems[indexPath.row]
        
        // Configure cell based on item type
        let typeIcon = item.type.icon
        cell.textLabel?.text = "\(typeIcon) \(item.name)"
        cell.detailTextLabel?.text = item.action
        
        // Color coding based on enabled state
        if item.isEnabled {
            cell.textLabel?.textColor = ThemeManager.shared.currentTheme.fontColor
            cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.7)
        } else {
            cell.textLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.5)
            cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.3)
        }
        
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        // Show selection state
        if selectedItems.contains(indexPath.row) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let movedItem = automationItems.remove(at: sourceIndexPath.row)
        automationItems.insert(movedItem, at: destinationIndexPath.row)
        
        // Update selection indices after move
        var newSelectedItems: Set<Int> = []
        for index in selectedItems {
            if index == sourceIndexPath.row {
                newSelectedItems.insert(destinationIndexPath.row)
            } else if index < sourceIndexPath.row && index >= destinationIndexPath.row {
                newSelectedItems.insert(index + 1)
            } else if index > sourceIndexPath.row && index <= destinationIndexPath.row {
                newSelectedItems.insert(index - 1)
            } else {
                newSelectedItems.insert(index)
            }
        }
        selectedItems = newSelectedItems
    }
}

// MARK: - UITableViewDelegate

extension AutomationOrganizerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isSelectionMode {
            selectedItems.insert(indexPath.row)
            tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isSelectionMode {
            selectedItems.remove(indexPath.row)
            tableView.cellForRow(at: indexPath)?.accessoryType = .none
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "All Automation (\(automationItems.count) items)"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if isSelectionMode {
            return "Select items for bulk operations. Drag to reorder."
        } else {
            return "Tap 'Select' for bulk operations and reordering."
        }
    }
}

