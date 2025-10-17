import UIKit
import CoreData

class WorldDisplayController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: WorldDisplayControllerDelegate?
    
    private var tableView: UITableView!
    private var worlds: [World] = []
    private var fetchedResultsController: NSFetchedResultsController<World>!
    private var showDeletedWorlds = false
    private let showDeletedSwitch = UISwitch()
    private let showDeletedLabel = UILabel()
    private var keyboardManager: KeyboardManager?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupFetchedResultsController()
        setupNotifications()
        setupShowDeletedUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Apply current theme
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        // Reload data
        try? fetchedResultsController.performFetch()
        tableView.reloadData()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        // Add visual styling to make the modal stand out
        view.layer.cornerRadius = 12
        view.layer.borderWidth = 1
        view.layer.borderColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.3).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 8
        view.layer.shadowOpacity = 0.3
        
        // Add tap gesture recognizer to dismiss when tapping outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        
        // Create navigation bar
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        navBar.barTintColor = ThemeManager.shared.terminalBackgroundColor
        navBar.tintColor = ThemeManager.shared.linkColor
        navBar.titleTextAttributes = [.foregroundColor: ThemeManager.shared.terminalTextColor]
        
        // Add border to navigation bar for better separation
        navBar.layer.borderWidth = 0.5
        navBar.layer.borderColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.2).cgColor
        navBar.clipsToBounds = true
        
        let navItem = UINavigationItem(title: "")
        
        // Create a custom title label for the left side
        let titleLabel = UILabel()
        titleLabel.text = "Worlds"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 17)
        titleLabel.textColor = ThemeManager.shared.terminalTextColor
        let titleButton = UIBarButtonItem(customView: titleLabel)
        
        // Add world button
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addWorldTapped)
        )
        
        // Reorder button
        let reorderButton = UIBarButtonItem(
            title: "Reorder",
            style: .plain,
            target: self,
            action: #selector(reorderButtonTapped)
        )
        
        // Close current world button
        let closeButton = UIBarButtonItem(
            title: "Close",
            style: .plain,
            target: self,
            action: #selector(closeCurrentWorldTapped)
        )
        
        navItem.leftBarButtonItem = titleButton
        navItem.rightBarButtonItems = [addButton, reorderButton, closeButton]
        navBar.setItems([navItem], animated: false)
        
        // Create table view
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.separatorColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.2)
        tableView.register(WorldTableViewCell.self, forCellReuseIdentifier: "WorldCell")
        
        // Add subtle border to table view
        tableView.layer.borderWidth = 0.5
        tableView.layer.borderColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.15).cgColor
        
        // Enable drag and drop for reordering
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        
        view.addSubview(navBar)
        view.addSubview(tableView)
        
        // Setup constraints - tableView will be updated after showDeleted UI is added
        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func closeCurrentWorldTapped() {
        // Delegate to the container's close sheet
        ClientContainer.shared?.showCloseWorldOptions()
    }
    
    private func setupFetchedResultsController() {
        let context = PersistenceController.shared.viewContext
        let request: NSFetchRequest<World> = World.fetchRequest()
        request.predicate = NSPredicate(format: "isHidden == NO")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \World.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \World.isDefault, ascending: false),
            NSSortDescriptor(keyPath: \World.name, ascending: true)
        ]
        
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        fetchedResultsController.delegate = self
        
        do {
            try fetchedResultsController.performFetch()
            let count = fetchedResultsController.fetchedObjects?.count ?? 0
            Logger.debug("Fetched \(count) worlds", category: Logger.coreData)
            
            // If no worlds exist, create some default ones
            if count == 0 {
                Logger.info("No worlds found, creating default worlds", category: Logger.coreData)
                createDefaultWorlds()
            }
        } catch {
            Logger.logCoreDataError("Error fetching worlds", error: error)
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .themeDidChange,
            object: nil
        )
        
        // Centralized keyboard handling
        keyboardManager = KeyboardManager(
            willShow: { [weak self] keyboardFrame, duration, curve in
                guard let self = self else { return }
                let keyboardHeight = keyboardFrame.height
                self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
                self.tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight, right: 0)
                UIView.animate(withDuration: min(duration, 0.3), delay: 0, options: [UIView.AnimationOptions(rawValue: curve), .allowUserInteraction]) {
                    self.view.layoutIfNeeded()
                }
            },
            willHide: { [weak self] duration, curve in
                guard let self = self else { return }
                self.tableView.contentInset = .zero
                self.tableView.scrollIndicatorInsets = .zero
                UIView.animate(withDuration: min(duration, 0.3), delay: 0, options: [UIView.AnimationOptions(rawValue: curve), .allowUserInteraction]) {
                    self.view.layoutIfNeeded()
                }
            }
        )
    }
    
    private func setupShowDeletedUI() {
        showDeletedLabel.text = "Show Deleted Worlds"
        showDeletedLabel.font = UIFont.systemFont(ofSize: 14)
        showDeletedLabel.textColor = ThemeManager.shared.terminalTextColor
        showDeletedSwitch.isOn = showDeletedWorlds
        showDeletedSwitch.addTarget(self, action: #selector(toggleShowDeletedWorlds), for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [showDeletedLabel, showDeletedSwitch])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        
        // Position the stack below the navigation bar
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44), // Below nav bar
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
        
        // Update tableView to start below the showDeleted UI
        tableView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8).isActive = true
    }
    
    // MARK: - Actions
    
    @objc private func backgroundTapped(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: view)
        
        // Get the navigation bar frame
        let navBarFrame = CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width, height: 44)
        
        // Check if tap is inside navigation bar
        if navBarFrame.contains(location) {
            return // Don't dismiss if tap is inside the navigation bar
        }
        
        // Check if tap is inside tableView
        if tableView.frame.contains(location) {
            return // Don't dismiss if tap is inside the table view
        }
        
        // Check if tap is inside the showDeleted UI stack
        if let stack = view.subviews.first(where: { $0 is UIStackView && $0.subviews.contains(showDeletedSwitch) }) {
            if stack.frame.contains(location) {
                return // Don't dismiss if tap is inside the show deleted UI
            }
        }
        
        // Otherwise, dismiss the view controller
        dismiss(animated: true)
    }
    
    @objc private func addWorldTapped() {
        print("WorldDisplayController: Add world button tapped")
        presentAddWorldInterface()
    }
    
    @objc private func reorderButtonTapped() {
        tableView.setEditing(!tableView.isEditing, animated: true)
        
        // Update button title
        if let navBar = view.subviews.compactMap({ $0 as? UINavigationBar }).first,
           let navItem = navBar.topItem {
            let reorderButton = navItem.rightBarButtonItems?.last
            reorderButton?.title = tableView.isEditing ? "Done" : "Reorder"
        }
    }
    
    private func presentAddWorldInterface() {
        let alert = UIAlertController(title: "Add New World", message: "Enter the details for the new MUD world", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "World Name (e.g., Aardwolf MUD)"
            textField.autocapitalizationType = .words
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Hostname (e.g., aardmud.org)"
            textField.autocapitalizationType = .none
            textField.keyboardType = .URL
        }
        
        alert.addTextField { textField in
            textField.placeholder = "Port (default: 23)"
            textField.keyboardType = .numberPad
            textField.text = "23"
        }
        
        alert.addAction(UIAlertAction(title: "Add World", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let hostname = alert.textFields?[1].text, !hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let portText = alert.textFields?[2].text, let port = Int32(portText), port > 0, port <= 65535 else {
                self?.showValidationError()
                return
            }
            
            self?.createNewWorld(name: name.trimmingCharacters(in: .whitespacesAndNewlines), 
                               hostname: hostname.trimmingCharacters(in: .whitespacesAndNewlines), 
                               port: port)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func createNewWorld(name: String, hostname: String, port: Int32) {
        let context = PersistenceController.shared.viewContext
        
        // Check if world with same NAME already exists (disallow duplicate names)
        let namePredicate = NSPredicate(format: "name == %@ AND isHidden == NO", name)
        let nameRequest: NSFetchRequest<World> = World.fetchRequest()
        nameRequest.predicate = namePredicate
        
        do {
            let existingWorlds = try context.fetch(nameRequest)
            if !existingWorlds.isEmpty {
                showDuplicateNameError(name: name)
                return
            }
            
            // Create new world (allow duplicate hostnames)
            let world = World.createWorld(in: context)
            world.name = name
            world.hostname = World.cleanedHostname(from: hostname)
            world.port = port
            world.isHidden = false
            world.lastModified = Date()
            
            try context.save()
            
            // Show success message
            let successAlert = UIAlertController(title: "World Added", message: "'\(name)' has been added successfully.", preferredStyle: .alert)
            successAlert.addAction(UIAlertAction(title: "OK", style: .default))
            present(successAlert, animated: true)
            
        } catch {
            showSaveError(error: error)
        }
    }
    
    private func showValidationError() {
        let alert = UIAlertController(title: "Invalid Input", message: "Please enter a valid world name, hostname, and port number (1-65535).", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showDuplicateNameError(name: String) {
        let alert = UIAlertController(title: "Duplicate World Name", message: "A world with the name '\(name)' already exists. Please choose a different name.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func showSaveError(error: Error) {
        let alert = UIAlertController(title: "Save Error", message: "Failed to save the new world: \(error.localizedDescription)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func themeChanged() {
        DispatchQueue.main.async {
            self.view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            self.tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
            self.tableView.separatorColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.3)
            self.tableView.reloadData()
        }
    }
    
    // MARK: - Keyboard Handling moved to KeyboardManager
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func toggleShowDeletedWorlds() {
        showDeletedWorlds = showDeletedSwitch.isOn
        fetchWorlds()
    }
    
    private func fetchWorlds() {
        // Update fetch request predicate based on showDeletedWorlds
        if showDeletedWorlds {
            fetchedResultsController.fetchRequest.predicate = nil // Show all
        } else {
            fetchedResultsController.fetchRequest.predicate = NSPredicate(format: "isHidden == NO")
        }
        do {
            try fetchedResultsController.performFetch()
            tableView.reloadData()
        } catch {
            Logger.logCoreDataError("Failed to fetch worlds", error: error)
        }
    }
}

// MARK: - UITableViewDataSource

extension WorldDisplayController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = fetchedResultsController.sections?[section].numberOfObjects ?? 0
        print("WorldDisplayController: numberOfRowsInSection returning \(count)")
        return count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorldCell", for: indexPath) as! WorldTableViewCell
        let world = fetchedResultsController.object(at: indexPath)
        cell.configure(with: world)
        return cell
    }
    
    // MARK: - Reordering Support
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Only allow reordering when not showing deleted worlds
        return !showDeletedWorlds
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let context = PersistenceController.shared.viewContext
        
        // Get all worlds from the fetched results controller
        guard let allWorlds = fetchedResultsController.fetchedObjects else { return }
        
        // Temporarily disable the fetched results controller delegate to prevent conflicts
        fetchedResultsController.delegate = nil
        
        // Create a mutable copy of the worlds array
        var reorderedWorlds = Array(allWorlds)
        
        // Move the world from source to destination
        let movedWorld = reorderedWorlds.remove(at: sourceIndexPath.row)
        reorderedWorlds.insert(movedWorld, at: destinationIndexPath.row)
        
        // Update sort orders based on new positions
        for (index, world) in reorderedWorlds.enumerated() {
            world.sortOrder = Int32(index)
            world.lastModified = Date()
        }
        
        // Save changes
        do {
            try context.save()
            Logger.debug("Successfully reordered worlds", category: Logger.coreData)
        } catch {
            Logger.logCoreDataError("Failed to save world reorder", error: error)
        }
        
        // Re-enable the delegate and perform a fresh fetch
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            tableView.reloadData()
        } catch {
            Logger.logCoreDataError("Failed to refresh after world reorder", error: error)
        }
    }
}

// MARK: - UITableViewDelegate

extension WorldDisplayController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let world = fetchedResultsController.fetchedObjects?[indexPath.row] else { return }
        
        print("WorldDisplayController: Selected world: \(world.name ?? "Unknown")")
        
        // Notify delegate of world selection
        delegate?.worldDisplayController(self, didSelectWorld: world.objectID)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    // MARK: - Swipe Actions
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let world = fetchedResultsController.object(at: indexPath)
        
        if world.isHidden {
            let restoreAction = UIContextualAction(style: .normal, title: "Restore") { [weak self] (action, view, completion) in
                self?.restoreWorld(world)
                completion(true)
            }
            restoreAction.backgroundColor = .systemGreen
            return UISwipeActionsConfiguration(actions: [restoreAction])
        } else {
            // Delete action
            let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] (action, view, completion) in
                self?.showDeleteConfirmation(for: world) { confirmed in
                    completion(confirmed)
                }
            }
            deleteAction.backgroundColor = .systemRed
            
            // Edit action
            let editAction = UIContextualAction(style: .normal, title: "Edit") { [weak self] (action, view, completion) in
                self?.editWorld(world)
                completion(true)
            }
            editAction.backgroundColor = .systemBlue
            
            let configuration = UISwipeActionsConfiguration(actions: [deleteAction, editAction])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }
    }
    
    // MARK: - World Management
    
    private func showDeleteConfirmation(for world: World, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "Delete World",
            message: "Are you sure you want to delete '\(world.name ?? "Unknown")'? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completion(false)
        })
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteWorld(world)
            completion(true)
        })
        
        present(alert, animated: true)
    }
    
    private func deleteWorld(_ world: World) {
        let context = world.managedObjectContext!
        
        // Check if this is the default world
        if world.isDefault {
            // Find another world to make default
            let request: NSFetchRequest<World> = World.fetchRequest()
            request.predicate = NSPredicate(format: "isHidden == NO AND self != %@", world)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \World.name, ascending: true)]
            request.fetchLimit = 1
            
            do {
                if let newDefault = try context.fetch(request).first {
                    newDefault.isDefault = true
                    newDefault.lastModified = Date()
                }
            } catch {
                Logger.logCoreDataError("Error finding new default world", error: error)
            }
        }
        
        // Mark world as hidden (soft delete) or delete completely
        world.isHidden = true
        world.lastModified = Date()
        
        do {
            try context.save()
            
            // Show success message
            let successAlert = UIAlertController(
                title: "World Deleted",
                message: "'\(world.name ?? "Unknown")' has been deleted successfully.",
                preferredStyle: .alert
            )
            successAlert.addAction(UIAlertAction(title: "OK", style: .default))
            present(successAlert, animated: true)
            
        } catch {
            Logger.logCoreDataError("Error deleting world", error: error)
            
            // Show error message
            let errorAlert = UIAlertController(
                title: "Delete Failed",
                message: "Failed to delete world: \(error.localizedDescription)",
                preferredStyle: .alert
            )
            errorAlert.addAction(UIAlertAction(title: "OK", style: .default))
            present(errorAlert, animated: true)
        }
    }
    
    private func editWorld(_ world: World) {
        let editController = WorldEditController(world: world)
        editController.delegate = self
        let navController = UINavigationController(rootViewController: editController)
        present(navController, animated: true)
    }
    
    private func restoreWorld(_ world: World) {
        let context = world.managedObjectContext!
        world.isHidden = false
        world.lastModified = Date()
        do {
            try context.save()
            let alert = UIAlertController(title: "World Restored", message: "'\(world.name ?? "Unknown")' has been restored.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            Logger.logCoreDataError("Error restoring world", error: error)
            let alert = UIAlertController(title: "Restore Failed", message: "Failed to restore world: \(error.localizedDescription)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension WorldDisplayController: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .fade)
            }
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        case .update:
            if let indexPath = indexPath {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        case .move:
            if let indexPath = indexPath, let newIndexPath = newIndexPath {
                tableView.deleteRows(at: [indexPath], with: .fade)
                tableView.insertRows(at: [newIndexPath], with: .fade)
            }
        @unknown default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }
}

// MARK: - WorldTableViewCell

class WorldTableViewCell: UITableViewCell {
    
    private let nameLabel = UILabel()
    private let hostLabel = UILabel()
    private let defaultIndicator = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .default
        isUserInteractionEnabled = true
        accessibilityTraits = .button
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = ThemeManager.shared.terminalFont
        nameLabel.textColor = ThemeManager.shared.terminalTextColor
        contentView.addSubview(nameLabel)
        
        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        hostLabel.font = UIFont(name: ThemeManager.shared.terminalFont.fontName, size: 12) ?? UIFont.systemFont(ofSize: 12)
        hostLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        contentView.addSubview(hostLabel)
        
        defaultIndicator.translatesAutoresizingMaskIntoConstraints = false
        defaultIndicator.font = UIFont(name: ThemeManager.shared.terminalFont.fontName, size: 10) ?? UIFont.systemFont(ofSize: 10)
        defaultIndicator.textColor = ThemeManager.shared.linkColor
        defaultIndicator.text = "DEFAULT"
        contentView.addSubview(defaultIndicator)
        
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: defaultIndicator.leadingAnchor, constant: -8),
            
            hostLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            hostLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hostLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            hostLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            defaultIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            defaultIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }
    
    func configure(with world: World) {
        nameLabel.text = world.name ?? "Unnamed World"
        hostLabel.text = "\(world.hostname ?? ""):\(world.port)"
        defaultIndicator.isHidden = !world.isDefault
        
        // Apply current theme
        nameLabel.textColor = ThemeManager.shared.terminalTextColor
        hostLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        defaultIndicator.textColor = ThemeManager.shared.linkColor
        backgroundColor = .clear
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        if selected {
            backgroundColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.1)
        } else {
            backgroundColor = .clear
        }
    }
}

// MARK: - WorldEditControllerDelegate

extension WorldDisplayController: WorldEditControllerDelegate {
    func worldEditController(_ controller: WorldEditController, didSaveWorld world: World) {
        // World was saved, dismiss the edit controller
        controller.dismiss(animated: true) {
            // Refresh the table view to show any changes
            self.tableView.reloadData()
        }
    }
    
    func worldEditControllerDidCancel(_ controller: WorldEditController) {
        // User cancelled editing, just dismiss
        controller.dismiss(animated: true)
    }
}

// MARK: - UITableViewDragDelegate

extension WorldDisplayController: UITableViewDragDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // Only allow dragging when not showing deleted worlds
        guard !showDeletedWorlds else { return [] }
        
        let world = fetchedResultsController.object(at: indexPath)
        let itemProvider = NSItemProvider(object: world.objectID.uriRepresentation().absoluteString as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = world
        return [dragItem]
    }
}

// MARK: - UITableViewDropDelegate

extension WorldDisplayController: UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        coordinator.items.forEach { dropItem in
            guard let sourceIndexPath = dropItem.sourceIndexPath else { return }
            
            // Just update the data model - the reloadData() in moveRowAt will handle the UI
            self.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        // Only allow reordering when not showing deleted worlds and during local drag session
        if session.localDragSession != nil && !showDeletedWorlds {
            return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        return UITableViewDropProposal(operation: .forbidden)
    }
}

// MARK: - Default Worlds Creation

extension WorldDisplayController {
    private func createDefaultWorlds() {
        let context = PersistenceController.shared.viewContext
        
        // Create a few sample worlds
        let worlds = [
            ("3Kingdoms", "3k.org", 3000),
            ("Aardwolf", "aardmud.org", 23),
            ("Discworld", "discworld.starturtle.net", 23),
            ("Batmud", "batmud.bat.org", 23)
        ]
        
        for (index, worldData) in worlds.enumerated() {
            let world = World(context: context)
            world.name = worldData.0
            world.hostname = worldData.1
            world.port = Int32(worldData.2)
            world.isDefault = (index == 0) // Make first one default
            world.isHidden = false
            world.sortOrder = Int32(index) // Set sort order
            world.lastModified = Date()
        }
        
        do {
            try context.save()
            Logger.info("Created default worlds", category: Logger.coreData)
            
            // Refresh the fetch controller
            try fetchedResultsController.performFetch()
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        } catch {
            Logger.logCoreDataError("Failed to create default worlds", error: error)
        }
    }
} 