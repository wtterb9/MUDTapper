import UIKit
import CoreData

protocol WorldEditControllerDelegate: AnyObject {
    func worldEditController(_ controller: WorldEditController, didSaveWorld world: World)
    func worldEditControllerDidCancel(_ controller: WorldEditController)
}

class WorldEditController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: WorldEditControllerDelegate?
    private var world: World!
    private var worldID: NSManagedObjectID!
    private var tableView: UITableView!
    private var isNewWorld: Bool = false
    
    // Form data
    private var worldName: String = ""
    private var hostname: String = ""
    private var port: String = ""
    private var connectCommand: String = ""
    
    // MARK: - Sections
    
    private enum Section: Int, CaseIterable {
        case basic = 0
        case triggers
        case aliases
        case gags
        case tickers
        
        var title: String {
            switch self {
            case .basic: return "World Settings"
            case .triggers: return "Triggers"
            case .aliases: return "Aliases"
            case .gags: return "Gags"
            case .tickers: return "Tickers"
            }
        }
        
        var footer: String? {
            switch self {
            case .basic: return nil
            case .triggers: return "Fire some actions whenever specified text is received."
            case .aliases: return "Create commands that expand into one or more actions."
            case .gags: return "Prevents specified text from appearing on screen."
            case .tickers: return "Send commands at regular intervals."
            }
        }
    }
    
    // MARK: - Initialization
    
    init(world: World) {
        super.init(nibName: nil, bundle: nil)
        self.world = world
        self.worldID = world.objectID
        self.isNewWorld = false
        loadWorldData()
    }
    
    init(newWorldInContext context: NSManagedObjectContext) {
        super.init(nibName: nil, bundle: nil)
        self.world = World(context: context)
        self.worldID = world.objectID
        self.isNewWorld = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupNavigationBar()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Apply current theme
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.reloadData()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.separatorColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.2)
        
        // Register cells
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BasicCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ActionCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ItemCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupNavigationBar() {
        title = isNewWorld ? "New World" : "Edit World"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
    }
    
    private func loadWorldData() {
        worldName = world.name ?? ""
        hostname = world.hostname ?? ""
        port = String(world.port)
        connectCommand = world.connectCommand ?? ""
    }
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        delegate?.worldEditControllerDidCancel(self)
    }
    
    @objc private func saveTapped() {
        // Validate required fields
        guard !worldName.isEmpty, !hostname.isEmpty, !port.isEmpty else {
            showAlert(title: "Missing Information", message: "Please fill in all required fields.")
            return
        }
        
        guard let portNumber = Int32(port) else {
            showAlert(title: "Invalid Port", message: "Please enter a valid port number.")
            return
        }
        
        // Check for duplicate world names (only if name changed or this is new world)
        let trimmedName = worldName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNewWorld || trimmedName != world.name {
            let context = world.managedObjectContext!
            let namePredicate = NSPredicate(format: "name == %@ AND isHidden == NO AND self != %@", trimmedName, world)
            let nameRequest: NSFetchRequest<World> = World.fetchRequest()
            nameRequest.predicate = namePredicate
            
            do {
                let existingWorlds = try context.fetch(nameRequest)
                if !existingWorlds.isEmpty {
                    showAlert(title: "Duplicate World Name", message: "A world with the name '\(trimmedName)' already exists. Please choose a different name.")
                    return
                }
            } catch {
                showAlert(title: "Validation Error", message: "Failed to validate world name: \(error.localizedDescription)")
                return
            }
        }
        
        // Save world data (allow duplicate hostnames)
        world.name = trimmedName
        world.hostname = hostname
        world.port = portNumber
        world.connectCommand = connectCommand.isEmpty ? nil : connectCommand
        world.lastModified = Date()
        
        if isNewWorld {
            world.isHidden = false
        }
        
        do {
            try world.managedObjectContext?.save()
            delegate?.worldEditController(self, didSaveWorld: world)
        } catch {
            showAlert(title: "Save Error", message: "Failed to save world: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Text Field Editing
    
    private func showTextFieldAlert(title: String, placeholder: String, currentValue: String, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = placeholder
            textField.text = currentValue
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            completion(text)
        })
        
        present(alert, animated: true)
    }
    
    // MARK: - Alias Management
    
    private func createNewAlias() {
        let editor = AliasEditorViewController(world: world)
        editor.onDismiss = { [weak self] in self?.tableView.reloadData() }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *), let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }
    
    private func editAlias(_ alias: Alias) {
        let editor = AliasEditorViewController(world: world, alias: alias)
        editor.onDismiss = { [weak self] in self?.tableView.reloadData() }
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *), let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }
    
    // MARK: - Trigger Management
    
    private func createNewTrigger() {
        let alert = UIAlertController(title: "New MushClient Trigger", message: "Create a MushClient-style trigger", preferredStyle: .actionSheet)
        
        // Quick trigger types
        alert.addAction(UIAlertAction(title: "🌟 Wildcard Trigger (*?)", style: .default) { [weak self] _ in
            self?.createMushClientTrigger(type: .wildcard)
        })
        
        alert.addAction(UIAlertAction(title: "📝 Simple Text Trigger", style: .default) { [weak self] _ in
            self?.createMushClientTrigger(type: .substring)
        })
        
        alert.addAction(UIAlertAction(title: "🔧 Regex Trigger", style: .default) { [weak self] _ in
            self?.createMushClientTrigger(type: .regex)
        })
        
        alert.addAction(UIAlertAction(title: "🎯 Exact Match", style: .default) { [weak self] _ in
            self?.createMushClientTrigger(type: .exact)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func createMushClientTrigger(type: Trigger.TriggerType) {
        let alert = UIAlertController(title: "\(type.displayName) Trigger", message: "\(type.description)\n\nExample: \(type.example)", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Trigger pattern"
            textField.text = type.example
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Commands (semicolon separated)"
            switch type {
            case .wildcard:
                textField.text = "say %1 said: %2"
            case .regex:
                textField.text = "say $1 said: $2"
            default:
                textField.text = "say Trigger activated!"
            }
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Label (optional)"
            textField.autocapitalizationType = .words
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let pattern = alert.textFields?[0].text, !pattern.isEmpty,
                  let commands = alert.textFields?[1].text, !commands.isEmpty else {
                return
            }
            
            let label = alert.textFields?[2].text?.isEmpty == false ? alert.textFields?[2].text : nil
            let context = self.world.managedObjectContext!
            
            _ = Trigger.createMushClientTrigger(
                pattern: pattern,
                commands: commands,
                type: type,
                options: [.enabled, .ignoreCase],
                priority: 50,
                group: nil,
                label: label,
                world: self.world,
                context: context
            )
            
            do {
                try context.save()
                self.tableView.reloadData()
            } catch {
                self.showAlert(title: "Error", message: "Failed to create trigger: \(error.localizedDescription)")
            }
        })
        
        present(alert, animated: true)
    }
    
    private func editTrigger(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Edit MushClient Trigger", message: trigger.displayName, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "✏️ Edit Pattern & Commands", style: .default) { [weak self] _ in
            self?.editTriggerBasics(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "⚙️ Edit Options & Priority", style: .default) { [weak self] _ in
            self?.editTriggerAdvanced(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "🎯 Test Pattern", style: .default) { [weak self] _ in
            self?.testTriggerPattern(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "📊 View Statistics", style: .default) { [weak self] _ in
            self?.showTriggerStatistics(trigger)
        })
        
        let toggleTitle = trigger.isActive ? "🔴 Disable" : "🟢 Enable"
        alert.addAction(UIAlertAction(title: toggleTitle, style: .default) { [weak self] _ in
            self?.toggleTrigger(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "🗑️ Delete", style: .destructive) { [weak self] _ in
            self?.deleteTrigger(trigger)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func editTriggerBasics(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Edit Trigger Basics", message: "Modify pattern and commands", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Pattern"
            textField.text = trigger.trigger
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Commands"
            textField.text = trigger.commands
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Label"
            textField.text = trigger.label
            textField.autocapitalizationType = .words
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            trigger.trigger = alert.textFields?[0].text
            trigger.commands = alert.textFields?[1].text
            trigger.label = alert.textFields?[2].text?.isEmpty == false ? alert.textFields?[2].text : nil
            trigger.lastModified = Date()
            
            do {
                try trigger.managedObjectContext?.save()
                self?.tableView.reloadData()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to save: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func editTriggerAdvanced(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Advanced Options", message: "Configure MushClient-style options", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Priority (0-100)"
            textField.text = "\(trigger.priority)"
            textField.keyboardType = .numberPad
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Group (optional)"
            textField.text = trigger.group
            textField.autocapitalizationType = .words
        }
        
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let priorityText = alert.textFields?[0].text, let priority = Int32(priorityText) {
                trigger.priority = priority
            }
            trigger.group = alert.textFields?[1].text?.isEmpty == false ? alert.textFields?[1].text : nil
            trigger.lastModified = Date()
            
            do {
                try trigger.managedObjectContext?.save()
                self?.tableView.reloadData()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to save: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func testTriggerPattern(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Test Pattern", message: "Test this trigger's pattern", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Enter test text"
            textField.text = "Biscuit says, 'test'"
        }
        
        alert.addAction(UIAlertAction(title: "Test", style: .default) { [weak self] _ in
            guard let testText = alert.textFields?[0].text, !testText.isEmpty else {
                return
            }
            
            let matches = trigger.matches(line: testText)
            let variables = trigger.captureVariables(from: testText)
            let commands = trigger.processedCommands(for: testText)
            
            var result = matches ? "✅ MATCHES" : "❌ NO MATCH"
            
            if matches {
                result += "\n\n📝 Variables:"
                for (key, value) in variables.sorted(by: { $0.key < $1.key }) {
                    result += "\n\(key): \"\(value)\""
                }
                
                result += "\n\n⚡ Commands:"
                for command in commands {
                    result += "\n• \(command)"
                }
            }
            
            self?.showAlert(title: "Test Result", message: result)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showTriggerStatistics(_ trigger: Trigger) {
        let message = """
        📊 Trigger Statistics
        
        Pattern: \(trigger.trigger ?? "Unknown")
        Type: \(trigger.triggerTypeEnum.displayName)
        Priority: \(trigger.priority)
        Group: \(trigger.group ?? "Default")
        
        🎯 Performance:
        • Match Count: \(trigger.matchCount)
        • Status: \(trigger.isActive ? "Active" : "Inactive")
        • Last Modified: \(trigger.lastModified?.formatted() ?? "Unknown")
        
        ⚙️ Options:
        \(trigger.triggerOptions.map { "• \($0.displayName)" }.joined(separator: "\n"))
        """
        
        showAlert(title: "Trigger Statistics", message: message)
    }
    
    private func toggleTrigger(_ trigger: Trigger) {
        var options = trigger.triggerOptions
        if options.contains(.enabled) {
            options.remove(.enabled)
        } else {
            options.insert(.enabled)
        }
        trigger.triggerOptions = options
        trigger.lastModified = Date()
        
        do {
            try trigger.managedObjectContext?.save()
            tableView.reloadData()
        } catch {
            showAlert(title: "Error", message: "Failed to toggle trigger: \(error.localizedDescription)")
        }
    }
    
    private func deleteTrigger(_ trigger: Trigger) {
        let alert = UIAlertController(title: "Delete Trigger", message: "Are you sure you want to delete '\(trigger.displayName)'?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            trigger.managedObjectContext?.delete(trigger)
            
            do {
                try trigger.managedObjectContext?.save()
                self?.tableView.reloadData()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to delete trigger: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    // MARK: - Gag Management
    
    private func createNewGag() {
        let alert = UIAlertController(title: "New Gag", message: "Create a new gag to hide text", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Text to hide (e.g., 'spam message')"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let text = alert.textFields?[0].text, !text.isEmpty else {
                return
            }
            
            let context = self.world.managedObjectContext!
            let gag = Gag(context: context)
            gag.gag = text
            gag.world = self.world
            gag.isHidden = false
            gag.lastModified = Date()
            
            do {
                try context.save()
                self.tableView.reloadData()
            } catch {
                self.showAlert(title: "Error", message: "Failed to create gag: \(error.localizedDescription)")
            }
        })
        
        present(alert, animated: true)
    }
    
    private func editGag(_ gag: Gag) {
        let alert = UIAlertController(title: "Edit Gag", message: "Modify the gag", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Text to hide"
            textField.text = gag.gag
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let text = alert.textFields?[0].text, !text.isEmpty else {
                return
            }
            
            gag.gag = text
            gag.lastModified = Date()
            
            do {
                try gag.managedObjectContext?.save()
                self?.tableView.reloadData()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to save gag: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            gag.managedObjectContext?.delete(gag)
            do {
                try gag.managedObjectContext?.save()
                self?.tableView.reloadData()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to delete gag: \(error.localizedDescription)")
            }
        })
        
        present(alert, animated: true)
    }
    
    // MARK: - Ticker Management
    
    private func createNewTicker() {
        let alert = UIAlertController(title: "New Ticker", message: "Create a new ticker", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Commands (e.g., 'look')"
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Interval in seconds (e.g., '30')"
            textField.keyboardType = .numberPad
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self = self,
                  let commands = alert.textFields?[0].text, !commands.isEmpty,
                  let intervalText = alert.textFields?[1].text, !intervalText.isEmpty,
                  let interval = Int32(intervalText) else {
                return
            }
            
            let context = self.world.managedObjectContext!
            let ticker = Ticker(context: context)
            ticker.commands = commands
            ticker.interval = Double(interval)
            ticker.world = self.world
            ticker.isHidden = false
            ticker.isEnabled = true
            ticker.lastModified = Date()
            
            do {
                try context.save()
                self.tableView.reloadData()
            } catch {
                self.showAlert(title: "Error", message: "Failed to create ticker: \(error.localizedDescription)")
            }
        })
        
        present(alert, animated: true)
    }
    
    private func editTicker(_ ticker: Ticker) {
        let alert = UIAlertController(title: "Edit Ticker", message: "Modify the ticker", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Commands"
            textField.text = ticker.commands
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Interval in seconds"
            textField.text = String(ticker.interval)
            textField.keyboardType = .numberPad
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let commands = alert.textFields?[0].text, !commands.isEmpty,
                  let intervalText = alert.textFields?[1].text, !intervalText.isEmpty,
                  let interval = Int32(intervalText) else {
                return
            }
            
            ticker.commands = commands
            ticker.interval = Double(interval)
            ticker.lastModified = Date()
            
            do {
                try ticker.managedObjectContext?.save()
                self?.tableView.reloadData()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to save ticker: \(error.localizedDescription)")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            ticker.managedObjectContext?.delete(ticker)
            do {
                try ticker.managedObjectContext?.save()
                self?.tableView.reloadData()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to delete ticker: \(error.localizedDescription)")
            }
        })
        
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension WorldEditController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        
        switch sectionType {
        case .basic:
            return 4 // Name, Hostname, Port, Connect Command
        case .triggers:
            if isNewWorld { return 0 }
            let triggers = Array(world.triggers ?? []).filter { !$0.isHidden }.sorted { $0.trigger ?? "" < $1.trigger ?? "" }
            return triggers.count + 1 // +1 for "New Trigger" button
        case .aliases:
            if isNewWorld { return 0 }
            let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.sorted { $0.name ?? "" < $1.name ?? "" }
            return aliases.count + 1 // +1 for "New Alias" button
        case .gags:
            if isNewWorld { return 0 }
            let gags = Array(world.gags ?? []).filter { !$0.isHidden }.sorted { $0.gag ?? "" < $1.gag ?? "" }
            return gags.count + 1 // +1 for "New Gag" button
        case .tickers:
            if isNewWorld { return 0 }
            let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }.sorted { $0.commands ?? "" < $1.commands ?? "" }
            return tickers.count + 1 // +1 for "New Ticker" button
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return Section(rawValue: section)?.footer
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        
        switch sectionType {
        case .basic:
            return configureBasicCell(for: indexPath)
        case .triggers:
            return configureTriggerCell(for: indexPath)
        case .aliases:
            return configureAliasCell(for: indexPath)
        case .gags:
            return configureGagCell(for: indexPath)
        case .tickers:
            return configureTickerCell(for: indexPath)
        }
    }
    
    private func configureBasicCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BasicCell", for: indexPath)
        
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "Name"
            cell.detailTextLabel?.text = worldName.isEmpty ? "Required" : worldName
        case 1:
            cell.textLabel?.text = "Hostname"
            cell.detailTextLabel?.text = hostname.isEmpty ? "Required" : hostname
        case 2:
            cell.textLabel?.text = "Port"
            cell.detailTextLabel?.text = port.isEmpty ? "Required" : port
        case 3:
            cell.textLabel?.text = "Connect Command"
            cell.detailTextLabel?.text = connectCommand.isEmpty ? "Optional" : connectCommand
        default:
            break
        }
        
        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cell.textLabel?.textColor = ThemeManager.shared.terminalTextColor
        cell.detailTextLabel?.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        
        return cell
    }
    
    private func configureTriggerCell(for indexPath: IndexPath) -> UITableViewCell {
        let triggers = Trigger.fetchActiveTriggersOrderedByPriority(for: world, context: world.managedObjectContext!)
        
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
            cell.textLabel?.text = "New MushClient Trigger"
            cell.textLabel?.textColor = ThemeManager.shared.linkColor
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath)
            let trigger = triggers[indexPath.row - 1]
            
            // Show MushClient-style information
            let statusIcon = trigger.isActive ? "🟢" : "🔴"
            let typeIcon = iconForTriggerType(trigger.triggerTypeEnum)
            let priorityText = trigger.priority != 50 ? " [\(trigger.priority)]" : ""
            let groupText = trigger.group != nil ? " (\(trigger.group!))" : ""
            let matchText = trigger.matchCount > 0 ? " •\(trigger.matchCount)" : ""
            
            cell.textLabel?.text = "\(statusIcon) \(typeIcon) \(trigger.displayName)\(priorityText)\(groupText)\(matchText)"
            cell.detailTextLabel?.text = trigger.commands
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            cell.textLabel?.textColor = ThemeManager.shared.terminalTextColor
            cell.detailTextLabel?.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
            return cell
        }
    }
    
    private func iconForTriggerType(_ type: Trigger.TriggerType) -> String {
        switch type {
        case .wildcard: return "🌟"
        case .regex: return "🔧"
        case .exact: return "🎯"
        case .substring: return "📝"
        case .beginsWith: return "▶️"
        case .endsWith: return "⏹️"
        }
    }
    
    private func configureAliasCell(for indexPath: IndexPath) -> UITableViewCell {
        let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.sorted { $0.name ?? "" < $1.name ?? "" }
        
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
            cell.textLabel?.text = "New Alias"
            cell.textLabel?.textColor = ThemeManager.shared.linkColor
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath)
            let alias = aliases[indexPath.row - 1]
            cell.textLabel?.text = alias.name
            cell.detailTextLabel?.text = alias.commands
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            cell.textLabel?.textColor = ThemeManager.shared.terminalTextColor
            cell.detailTextLabel?.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
            return cell
        }
    }
    
    private func configureGagCell(for indexPath: IndexPath) -> UITableViewCell {
        let gags = Array(world.gags ?? []).filter { !$0.isHidden }.sorted { $0.gag ?? "" < $1.gag ?? "" }
        
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
            cell.textLabel?.text = "New Gag"
            cell.textLabel?.textColor = ThemeManager.shared.linkColor
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath)
            let gag = gags[indexPath.row - 1]
            cell.textLabel?.text = gag.gag
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            cell.textLabel?.textColor = ThemeManager.shared.terminalTextColor
            return cell
        }
    }
    
    private func configureTickerCell(for indexPath: IndexPath) -> UITableViewCell {
        let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }.sorted { $0.commands ?? "" < $1.commands ?? "" }
        
        if indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ActionCell", for: indexPath)
            cell.textLabel?.text = "New Ticker"
            cell.textLabel?.textColor = ThemeManager.shared.linkColor
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ItemCell", for: indexPath)
            let ticker = tickers[indexPath.row - 1]
            cell.textLabel?.text = ticker.commands
            cell.detailTextLabel?.text = "\(ticker.interval)s"
            cell.accessoryType = .disclosureIndicator
            cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            cell.textLabel?.textColor = ThemeManager.shared.terminalTextColor
            cell.detailTextLabel?.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension WorldEditController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let sectionType = Section(rawValue: indexPath.section) else { return }
        
        switch sectionType {
        case .basic:
            handleBasicCellSelection(at: indexPath)
        case .triggers:
            handleTriggerCellSelection(at: indexPath)
        case .aliases:
            handleAliasCellSelection(at: indexPath)
        case .gags:
            handleGagCellSelection(at: indexPath)
        case .tickers:
            handleTickerCellSelection(at: indexPath)
        }
    }
    
    private func handleBasicCellSelection(at indexPath: IndexPath) {
        switch indexPath.row {
        case 0:
            showTextFieldAlert(title: "World Name", placeholder: "Enter world name", currentValue: worldName) { [weak self] value in
                self?.worldName = value
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
        case 1:
            showTextFieldAlert(title: "Hostname", placeholder: "Enter hostname", currentValue: hostname) { [weak self] value in
                self?.hostname = value
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
        case 2:
            showTextFieldAlert(title: "Port", placeholder: "Enter port number", currentValue: port) { [weak self] value in
                self?.port = value
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
        case 3:
            showTextFieldAlert(title: "Connect Command", placeholder: "Enter connect command (optional)", currentValue: connectCommand) { [weak self] value in
                self?.connectCommand = value
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
        default:
            break
        }
    }
    
    private func handleTriggerCellSelection(at indexPath: IndexPath) {
        if indexPath.row == 0 {
            createNewTrigger()
        } else {
            let triggers = Array(world.triggers ?? []).filter { !$0.isHidden }.sorted { $0.trigger ?? "" < $1.trigger ?? "" }
            let trigger = triggers[indexPath.row - 1]
            editTrigger(trigger)
        }
    }
    
    private func handleAliasCellSelection(at indexPath: IndexPath) {
        if indexPath.row == 0 {
            createNewAlias()
        } else {
            let aliases = Array(world.aliases ?? []).filter { !$0.isHidden }.sorted { $0.name ?? "" < $1.name ?? "" }
            let alias = aliases[indexPath.row - 1]
            editAlias(alias)
        }
    }
    
    private func handleGagCellSelection(at indexPath: IndexPath) {
        if indexPath.row == 0 {
            createNewGag()
        } else {
            let gags = Array(world.gags ?? []).filter { !$0.isHidden }.sorted { $0.gag ?? "" < $1.gag ?? "" }
            let gag = gags[indexPath.row - 1]
            editGag(gag)
        }
    }
    
    private func handleTickerCellSelection(at indexPath: IndexPath) {
        if indexPath.row == 0 {
            createNewTicker()
        } else {
            let tickers = Array(world.tickers ?? []).filter { !$0.isHidden }.sorted { $0.commands ?? "" < $1.commands ?? "" }
            let ticker = tickers[indexPath.row - 1]
            editTicker(ticker)
        }
    }
} 