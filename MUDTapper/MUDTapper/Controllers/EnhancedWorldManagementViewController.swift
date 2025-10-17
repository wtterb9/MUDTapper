import UIKit
import CoreData

class EnhancedWorldManagementViewController: UIViewController {
    
    // MARK: - Properties
    
    private var collectionView: UICollectionView!
    private var searchController: UISearchController!
    private var segmentedControl: UISegmentedControl!
    private var addButton: UIBarButtonItem!
    
    private var worlds: [World] = []
    private var filteredWorlds: [World] = []
    private var currentFilter: WorldFilter = .all
    private var isSearching = false
    
    weak var delegate: WorldManagementDelegate?
    
    // MARK: - Filter Types
    
    enum WorldFilter: Int, CaseIterable {
        case all = 0
        case favorites
        case recent
        case connected
        
        var title: String {
            switch self {
            case .all: return "All"
            case .favorites: return "Favorites"
            case .recent: return "Recent"
            case .connected: return "Connected"
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "🌍 World Management"
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSearchController()
        loadWorlds()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshWorlds()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        setupNavigationBar()
        setupFilterSegments()
        setupCollectionView()
        setupConstraints()
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addWorldButtonTapped)
        )
        
        let organizerButton = UIBarButtonItem(
            image: UIImage(systemName: "folder.badge.gearshape"),
            style: .plain,
            target: self,
            action: #selector(organizerButtonTapped)
        )
        
        navigationItem.rightBarButtonItems = [addButton, organizerButton]
    }
    
    private func setupFilterSegments() {
        let titles = WorldFilter.allCases.map { $0.title }
        segmentedControl = UISegmentedControl(items: titles)
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.addTarget(self, action: #selector(filterChanged(_:)), for: .valueChanged)
        
        view.addSubview(segmentedControl)
    }
    
    private func setupCollectionView() {
        let layout = createCollectionViewLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        // Enable drag and drop for reordering
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.reorderingCadence = .fast
        
        // Register cells
        collectionView.register(WorldCardCell.self, forCellWithReuseIdentifier: "WorldCardCell")
        collectionView.register(AddWorldCell.self, forCellWithReuseIdentifier: "AddWorldCell")
        collectionView.register(WorldSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "WorldSectionHeader")
        
        view.addSubview(collectionView)
    }
    
    private func createCollectionViewLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            // World cards section
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(120)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(120)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            
            // Add header
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(44)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            
            return section
        }
        
        return layout
    }
    
    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search worlds..."
        navigationItem.searchController = searchController
        definesPresentationContext = true
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            collectionView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadWorlds() {
        let context = PersistenceController.shared.viewContext
        let request: NSFetchRequest<World> = World.fetchRequest()
        request.predicate = NSPredicate(format: "isHidden == NO")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \World.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \World.isFavorite, ascending: false),
            NSSortDescriptor(keyPath: \World.lastConnected, ascending: false),
            NSSortDescriptor(keyPath: \World.name, ascending: true)
        ]
        
        do {
            worlds = try context.fetch(request)
            initializeSortOrdersIfNeeded()
            applyCurrentFilter()
        } catch {
            print("Error loading worlds: \(error)")
        }
    }
    
    private func initializeSortOrdersIfNeeded() {
        let context = PersistenceController.shared.viewContext
        var needsSave = false
        
        // Initialize sort orders for worlds that don't have them
        for (index, world) in worlds.enumerated() {
            if world.sortOrder == 0 && index > 0 { // Assume 0 means unset (except for first item)
                world.sortOrder = Int32(index)
                needsSave = true
            }
        }
        
        if needsSave {
            do {
                try context.save()
            } catch {
                print("Failed to initialize sort orders: \(error)")
            }
        }
    }
    
    private func refreshWorlds() {
        loadWorlds()
        collectionView.reloadData()
    }
    
    private func applyCurrentFilter() {
        let baseWorlds = isSearching ? filteredWorlds : worlds
        
        switch currentFilter {
        case .all:
            filteredWorlds = baseWorlds
            
        case .favorites:
            filteredWorlds = baseWorlds.filter { $0.isFavorite }
            
        case .recent:
            let oneWeekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            filteredWorlds = baseWorlds.filter { world in
                guard let lastConnected = world.lastConnected else { return false }
                return lastConnected > oneWeekAgo
            }
            
        case .connected:
            // Check actual connection status with ClientContainer
            filteredWorlds = baseWorlds.filter { world in
                ClientContainer.shared?.isWorldConnected(world.objectID) ?? false
            }
        }
        
        collectionView.reloadData()
    }
    
    // MARK: - Actions
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func addWorldButtonTapped() {
        showWorldCreationOptions()
    }
    
    @objc private func organizerButtonTapped() {
        showWorldOrganizer()
    }
    
    @objc private func filterChanged(_ sender: UISegmentedControl) {
        currentFilter = WorldFilter(rawValue: sender.selectedSegmentIndex) ?? .all
        applyCurrentFilter()
    }
    
    // MARK: - World Management Actions
    
    private func showWorldCreationOptions() {
        let alert = UIAlertController(title: "Add New World", message: "Choose how to add a new world", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "✏️ Create Custom World", style: .default) { [weak self] _ in
            self?.createCustomWorld()
        })
        
        alert.addAction(UIAlertAction(title: "📋 Import from Clipboard", style: .default) { [weak self] _ in
            self?.importWorldFromClipboard()
        })
        
        alert.addAction(UIAlertAction(title: "📄 Import from File", style: .default) { [weak self] _ in
            self?.importWorldFromFile()
        })
        
        alert.addAction(UIAlertAction(title: "🌐 Browse World Directory", style: .default) { [weak self] _ in
            self?.browseWorldDirectory()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = addButton
        }
        
        present(alert, animated: true)
    }
    
    private func createCustomWorld() {
        let context = PersistenceController.shared.viewContext
        let worldEditController = WorldEditController(newWorldInContext: context)
        worldEditController.delegate = self
        
        let navController = UINavigationController(rootViewController: worldEditController)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func importWorldFromClipboard() {
        guard let clipboardText = UIPasteboard.general.string else {
            showAlert(title: "No Data", message: "No text found in clipboard.")
            return
        }
        
        // Parse clipboard for world data (hostname:port format)
        parseAndCreateWorld(from: clipboardText, source: "clipboard")
    }
    
    private func importWorldFromFile() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.text, .json])
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .pageSheet
        present(documentPicker, animated: true)
    }
    
    private func browseWorldDirectory() {
        let worldDirectoryVC = WorldDirectoryViewController()
        let navController = UINavigationController(rootViewController: worldDirectoryVC)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func showWorldOrganizer() {
        let organizerVC = WorldOrganizerViewController(worlds: worlds)
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
    
    private func parseAndCreateWorld(from text: String, source: String) {
        // Simple parsing for hostname:port format
        let lines = text.components(separatedBy: .newlines)
        var createdWorlds = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let components = trimmed.components(separatedBy: ":")
            if components.count >= 2,
               let port = Int32(components[1]) {
                let hostname = components[0]
                createWorld(name: hostname, hostname: hostname, port: port)
                createdWorlds += 1
            }
        }
        
        if createdWorlds > 0 {
            showAlert(title: "Import Successful", message: "Created \(createdWorlds) world(s) from \(source).")
            refreshWorlds()
        } else {
            showAlert(title: "Import Failed", message: "No valid world data found in \(source).")
        }
    }
    
    private func createWorld(name: String, hostname: String, port: Int32) {
        let context = PersistenceController.shared.viewContext
        let world = World(context: context)
        world.name = name
        world.hostname = hostname
        world.port = port
        world.isHidden = false
        world.isFavorite = false
        world.lastModified = Date()
        
        do {
            try context.save()
        } catch {
            print("Error creating world: \(error)")
        }
    }
    
    private func showWorldActions(for world: World) {
        let alert = UIAlertController(
            title: world.name ?? "Unknown World",
            message: "\(world.hostname ?? ""):\(world.port)",
            preferredStyle: .actionSheet
        )
        
        // Connection actions
        let isConnected = ClientContainer.shared?.isWorldConnected(world.objectID) ?? false
        
        if isConnected {
            alert.addAction(UIAlertAction(title: "🔌 Disconnect", style: .default) { [weak self] _ in
                ClientContainer.shared?.disconnectWorld(world.objectID)
                self?.refreshWorlds()
            })
            
            alert.addAction(UIAlertAction(title: "🔄 Switch to Session", style: .default) { [weak self] _ in
                ClientContainer.shared?.switchToWorld(world.objectID)
                self?.delegate?.worldManagement(self!, didSelectWorld: world)
                self?.dismiss(animated: true)
            })
        } else {
            alert.addAction(UIAlertAction(title: "🚀 Connect", style: .default) { [weak self] _ in
                self?.delegate?.worldManagement(self!, didSelectWorld: world)
                self?.dismiss(animated: true)
            })
        }
        
        // Management actions
        alert.addAction(UIAlertAction(title: "✏️ Edit", style: .default) { [weak self] _ in
            self?.editWorld(world)
        })
        
        alert.addAction(UIAlertAction(title: "📋 Duplicate", style: .default) { [weak self] _ in
            self?.duplicateWorld(world)
        })
        
        let favoriteTitle = world.isFavorite ? "💔 Remove from Favorites" : "❤️ Add to Favorites"
        alert.addAction(UIAlertAction(title: favoriteTitle, style: .default) { [weak self] _ in
            self?.toggleWorldFavorite(world)
        })
        
        alert.addAction(UIAlertAction(title: "📤 Export", style: .default) { [weak self] _ in
            self?.exportWorld(world)
        })
        
        alert.addAction(UIAlertAction(title: "��️ Delete", style: .destructive) { [weak self] _ in
            self?.deleteWorld(world)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func editWorld(_ world: World) {
        let worldEditController = WorldEditController(world: world)
        worldEditController.delegate = self
        
        let navController = UINavigationController(rootViewController: worldEditController)
        navController.modalPresentationStyle = .pageSheet
        
        if #available(iOS 15.0, *) {
            if let sheet = navController.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        
        present(navController, animated: true)
    }
    
    private func duplicateWorld(_ world: World) {
        let context = PersistenceController.shared.viewContext
        let newWorld = World(context: context)
        
        newWorld.name = (world.name ?? "World") + " Copy"
        newWorld.hostname = world.hostname
        newWorld.port = world.port
        newWorld.isSecure = world.isSecure
        newWorld.connectCommand = world.connectCommand
        newWorld.isHidden = false
        newWorld.isFavorite = false
        newWorld.lastModified = Date()
        
        do {
            try context.save()
            showAlert(title: "World Duplicated", message: "Created a copy of \(world.name ?? "the world").")
            refreshWorlds()
        } catch {
            showAlert(title: "Error", message: "Failed to duplicate world: \(error.localizedDescription)")
        }
    }
    
    private func toggleWorldFavorite(_ world: World) {
        world.isFavorite.toggle()
        
        do {
            try world.managedObjectContext?.save()
            refreshWorlds()
        } catch {
            showAlert(title: "Error", message: "Failed to update favorite status.")
        }
    }
    
    private func exportWorld(_ world: World) {
        let exportData = """
        World: \(world.name ?? "Unknown")
        Hostname: \(world.hostname ?? "")
        Port: \(world.port)
        Secure: \(world.isSecure)
        Connect Command: \(world.connectCommand ?? "")
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [exportData],
            applicationActivities: nil
        )
        
        present(activityVC, animated: true)
    }
    
    private func deleteWorld(_ world: World) {
        let alert = UIAlertController(
            title: "Delete World",
            message: "Are you sure you want to delete '\(world.name ?? "this world")'? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            world.isHidden = true
            
            do {
                try world.managedObjectContext?.save()
                self?.refreshWorlds()
            } catch {
                self?.showAlert(title: "Error", message: "Failed to delete world.")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        ErrorPresenter.showError(title: title, message: message)
    }
}

// MARK: - UICollectionViewDataSource

extension EnhancedWorldManagementViewController: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return filteredWorlds.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "WorldCardCell", for: indexPath) as! WorldCardCell
        let world = filteredWorlds[indexPath.item]
        
        let isConnected = ClientContainer.shared?.isWorldConnected(world.objectID) ?? false
        cell.configure(with: world, isConnected: isConnected)
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "WorldSectionHeader", for: indexPath) as! WorldSectionHeader
        
        let count = filteredWorlds.count
        let filterName = currentFilter.title
        let canReorder = count > 1 && currentFilter == .all && !isSearching
        let subtitle = canReorder ? "\(count) worlds • Drag to reorder" : "\(count) world\(count == 1 ? "" : "s")"
        header.configure(title: "\(filterName) Worlds", subtitle: subtitle)
        
        return header
    }
}

// MARK: - UICollectionViewDelegate

extension EnhancedWorldManagementViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let world = filteredWorlds[indexPath.item]
        showWorldActions(for: world)
    }
}

// MARK: - UISearchResultsUpdating

extension EnhancedWorldManagementViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text else { return }
        
        isSearching = !searchText.isEmpty
        
        if isSearching {
            filteredWorlds = worlds.filter { world in
                let nameMatch = world.name?.localizedCaseInsensitiveContains(searchText) ?? false
                let hostnameMatch = world.hostname?.localizedCaseInsensitiveContains(searchText) ?? false
                return nameMatch || hostnameMatch
            }
        } else {
            applyCurrentFilter()
        }
        
        collectionView.reloadData()
    }
}

// MARK: - UIDocumentPickerDelegate

extension EnhancedWorldManagementViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        do {
            let content = try String(contentsOf: url)
            parseAndCreateWorld(from: content, source: "file")
        } catch {
            showAlert(title: "Import Error", message: "Failed to read file: \(error.localizedDescription)")
        }
    }
}

// MARK: - UICollectionViewDragDelegate

extension EnhancedWorldManagementViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        // Only allow dragging in "All" filter mode and when not searching
        guard currentFilter == .all && !isSearching else { return [] }
        
        let world = filteredWorlds[indexPath.item]
        let itemProvider = NSItemProvider(object: world.objectID.uriRepresentation().absoluteString as NSString)
        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = world
        return [dragItem]
    }
}

// MARK: - UICollectionViewDropDelegate

extension EnhancedWorldManagementViewController: UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        coordinator.items.forEach { dropItem in
            guard let sourceIndexPath = dropItem.sourceIndexPath,
                  let world = dropItem.dragItem.localObject as? World else { return }
            
            // Perform the move
            collectionView.performBatchUpdates({
                // Update the data source
                filteredWorlds.remove(at: sourceIndexPath.item)
                filteredWorlds.insert(world, at: destinationIndexPath.item)
                
                // Move the collection view item
                collectionView.moveItem(at: sourceIndexPath, to: destinationIndexPath)
            }) { _ in
                // Update sort orders in Core Data
                self.updateSortOrders()
            }
        }
    }
    
    private func updateSortOrders() {
        let context = PersistenceController.shared.viewContext
        
        // Update sort orders based on current position in filteredWorlds
        // We need to update the main worlds array and reassign sort orders to all worlds
        for (index, world) in filteredWorlds.enumerated() {
            world.sortOrder = Int32(index)
            world.lastModified = Date()
        }
        
        // Update the main worlds array to match the new order
        worlds = filteredWorlds
        
        do {
            try context.save()
        } catch {
            print("Failed to update sort orders: \(error)")
            showAlert(title: "Error", message: "Failed to save world order: \(error.localizedDescription)")
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // Only allow reordering in "All" filter mode and when not searching
        if session.localDragSession != nil && currentFilter == .all && !isSearching {
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        return UICollectionViewDropProposal(operation: .forbidden)
    }
}

// MARK: - WorldEditControllerDelegate

extension EnhancedWorldManagementViewController: WorldEditControllerDelegate {
    
    func worldEditController(_ controller: WorldEditController, didSaveWorld world: World) {
        controller.dismiss(animated: true)
        refreshWorlds()
    }
    
    func worldEditControllerDidCancel(_ controller: WorldEditController) {
        controller.dismiss(animated: true)
    }
}

// MARK: - WorldOrganizerDelegate

protocol WorldOrganizerDelegate: AnyObject {
    func worldOrganizerDidUpdateWorlds(_ organizer: WorldOrganizerViewController)
}

extension EnhancedWorldManagementViewController: WorldOrganizerDelegate {
    
    func worldOrganizerDidUpdateWorlds(_ organizer: WorldOrganizerViewController) {
        refreshWorlds()
    }
}

// MARK: - WorldManagementDelegate

protocol WorldManagementDelegate: AnyObject {
    func worldManagement(_ controller: EnhancedWorldManagementViewController, didSelectWorld world: World)
}

// MARK: - Supporting View Controllers

class WorldDirectoryViewController: UIViewController {
    
    private var tableView: UITableView!
    private var searchController: UISearchController!
    private var worldDirectories: [WorldDirectoryCategory] = []
    private var filteredDirectories: [WorldDirectoryCategory] = []
    private var isSearching: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "World Directory"
        setupUI()
        loadWorldDirectories()
    }
    
    private func setupUI() {
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        
        // Setup search controller
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search MUD worlds..."
        navigationItem.searchController = searchController
        definesPresentationContext = true
        
        // Setup table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WorldCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func loadWorldDirectories() {
        worldDirectories = [
            WorldDirectoryCategory(
                name: "Popular MUDs",
                description: "Well-known and active MUD servers",
                worlds: [
                    WorldDirectoryEntry(
                        name: "Aardwolf MUD",
                        hostname: "aardmud.org",
                        port: 23,
                        description: "One of the most popular MUDs with unique features and an active community.",
                        playerCount: "200-300",
                        theme: "Fantasy",
                        codebase: "ROM",
                        website: "https://www.aardwolf.com"
                    ),
                    WorldDirectoryEntry(
                        name: "Achaea",
                        hostname: "achaea.com",
                        port: 23,
                        description: "A commercial MUD with excellent roleplay and PvP systems.",
                        playerCount: "100-200",
                        theme: "Fantasy",
                        codebase: "Rapture",
                        website: "https://www.achaea.com"
                    ),
                    WorldDirectoryEntry(
                        name: "Discworld MUD",
                        hostname: "discworld.starturtle.net",
                        port: 23,
                        description: "Based on Terry Pratchett's Discworld novels.",
                        playerCount: "50-100",
                        theme: "Comedy Fantasy",
                        codebase: "LPC",
                        website: "https://discworld.starturtle.net"
                    )
                ]
            ),
            WorldDirectoryCategory(
                name: "Role-Playing",
                description: "MUDs focused on roleplay and storytelling",
                worlds: [
                    WorldDirectoryEntry(
                        name: "Armageddon MUD",
                        hostname: "ginka.armageddon.org",
                        port: 4050,
                        description: "Harsh desert world with enforced roleplay and permadeath.",
                        playerCount: "30-80",
                        theme: "Post-Apocalyptic",
                        codebase: "Diku",
                        website: "https://www.armageddon.org"
                    ),
                    WorldDirectoryEntry(
                        name: "Shadows of Isildur",
                        hostname: "middle-earth.us",
                        port: 4000,
                        description: "Lord of the Rings themed roleplay MUD.",
                        playerCount: "20-50",
                        theme: "Middle-earth",
                        codebase: "SOI",
                        website: "http://www.middle-earth.us"
                    )
                ]
            ),
            WorldDirectoryCategory(
                name: "Player vs Player",
                description: "Combat-focused MUDs with PvP elements",
                worlds: [
                    WorldDirectoryEntry(
                        name: "Retribution MUD",
                        hostname: "ret.org",
                        port: 3000,
                        description: "Fast-paced PvP MUD with multiple classes and races.",
                        playerCount: "40-80",
                        theme: "Fantasy PvP",
                        codebase: "LP",
                        website: "https://www.ret.org"
                    ),
                    WorldDirectoryEntry(
                        name: "Carrion Fields",
                        hostname: "carrionfields.net",
                        port: 9999,
                        description: "Hardcore PvP with permanent death and roleplay.",
                        playerCount: "30-60",
                        theme: "Dark Fantasy",
                        codebase: "ROM",
                        website: "https://www.carrionfields.net"
                    )
                ]
            ),
            WorldDirectoryCategory(
                name: "Classic",
                description: "Traditional and retro MUDs",
                worlds: [
                    WorldDirectoryEntry(
                        name: "Ancient Anguish",
                        hostname: "ancient.anguish.org",
                        port: 2222,
                        description: "One of the oldest continuously running MUDs.",
                        playerCount: "10-30",
                        theme: "Medieval Fantasy",
                        codebase: "LPC",
                        website: "https://www.anguish.org"
                    ),
                    WorldDirectoryEntry(
                        name: "DikuMUD",
                        hostname: "dikumud.com",
                        port: 4000,
                        description: "The original DikuMUD that started it all.",
                        playerCount: "5-20",
                        theme: "Classic Fantasy",
                        codebase: "Diku",
                        website: "http://www.dikumud.com"
                    )
                ]
            )
        ]
        
        filteredDirectories = worldDirectories
        tableView.reloadData()
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    private func importWorld(_ worldEntry: WorldDirectoryEntry) {
        let alert = UIAlertController(
            title: "Import World",
            message: "Import \(worldEntry.name) to your world list?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Import", style: .default) { _ in
            self.performWorldImport(worldEntry)
        })
        
        present(alert, animated: true)
    }
    
    private func performWorldImport(_ worldEntry: WorldDirectoryEntry) {
        let context = PersistenceController.shared.viewContext
        
        // Check if world already exists
        let fetchRequest: NSFetchRequest<World> = World.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "hostname == %@ AND port == %d", worldEntry.hostname, Int32(worldEntry.port))
        
        do {
            let existingWorlds = try context.fetch(fetchRequest)
            if !existingWorlds.isEmpty {
                showAlert(title: "World Exists", message: "A world with this hostname and port already exists.")
                return
            }
        } catch {
            showAlert(title: "Error", message: "Failed to check for existing worlds: \(error.localizedDescription)")
            return
        }
        
        // Create new world
        let world = World(context: context)
        world.name = worldEntry.name
        world.hostname = worldEntry.hostname
        world.port = Int32(worldEntry.port)
        world.isDefault = false
        world.isFavorite = false
        world.isHidden = false
        world.isSecure = false
        world.autoConnect = false
        world.lastModified = Date()
        
        do {
            try context.save()
            showAlert(title: "Success", message: "\(worldEntry.name) has been imported to your world list!")
        } catch {
            showAlert(title: "Error", message: "Failed to import world: \(error.localizedDescription)")
        }
    }
    
    private func showWorldDetails(_ worldEntry: WorldDirectoryEntry) {
        let detailsVC = WorldDirectoryDetailViewController(worldEntry: worldEntry)
        detailsVC.delegate = self
        let navController = UINavigationController(rootViewController: detailsVC)
        present(navController, animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        ErrorPresenter.showError(title: title, message: message)
    }
}

// MARK: - UITableViewDataSource

extension WorldDirectoryViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return filteredDirectories.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredDirectories[section].worlds.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorldCell", for: indexPath)
        let world = filteredDirectories[indexPath.section].worlds[indexPath.row]
        
        cell.textLabel?.text = world.name
        cell.detailTextLabel?.text = "\(world.hostname):\(world.port) • \(world.playerCount) players"
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cell.textLabel?.textColor = ThemeManager.shared.terminalTextColor
        cell.detailTextLabel?.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        cell.accessoryType = .disclosureIndicator
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return filteredDirectories[section].name
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return filteredDirectories[section].description
    }
}

// MARK: - UITableViewDelegate

extension WorldDirectoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let world = filteredDirectories[indexPath.section].worlds[indexPath.row]
        showWorldDetails(world)
    }
}

// MARK: - UISearchResultsUpdating

extension WorldDirectoryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text else { return }
        
        if searchText.isEmpty {
            isSearching = false
            filteredDirectories = worldDirectories
        } else {
            isSearching = true
            filteredDirectories = worldDirectories.compactMap { category in
                let filteredWorlds = category.worlds.filter { world in
                    return world.name.lowercased().contains(searchText.lowercased()) ||
                           world.hostname.lowercased().contains(searchText.lowercased()) ||
                           world.theme.lowercased().contains(searchText.lowercased()) ||
                           world.description.lowercased().contains(searchText.lowercased())
                }
                
                if filteredWorlds.isEmpty {
                    return nil
                } else {
                    return WorldDirectoryCategory(
                        name: category.name,
                        description: category.description,
                        worlds: filteredWorlds
                    )
                }
            }
        }
        
        tableView.reloadData()
    }
}

// MARK: - WorldDirectoryDetailDelegate

extension WorldDirectoryViewController: WorldDirectoryDetailDelegate {
    func worldDirectoryDetail(_ controller: WorldDirectoryDetailViewController, didRequestImport worldEntry: WorldDirectoryEntry) {
        controller.dismiss(animated: true) {
            self.performWorldImport(worldEntry)
        }
    }
}

// MARK: - Supporting Classes

struct WorldDirectoryCategory {
    let name: String
    let description: String
    let worlds: [WorldDirectoryEntry]
}

struct WorldDirectoryEntry {
    let name: String
    let hostname: String
    let port: Int
    let description: String
    let playerCount: String
    let theme: String
    let codebase: String
    let website: String
}

protocol WorldDirectoryDetailDelegate: AnyObject {
    func worldDirectoryDetail(_ controller: WorldDirectoryDetailViewController, didRequestImport worldEntry: WorldDirectoryEntry)
}

class WorldDirectoryDetailViewController: UIViewController {
    
    weak var delegate: WorldDirectoryDetailDelegate?
    private let worldEntry: WorldDirectoryEntry
    private var tableView: UITableView!
    
    init(worldEntry: WorldDirectoryEntry) {
        self.worldEntry = worldEntry
        super.init(nibName: nil, bundle: nil)
        title = worldEntry.name
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Import", style: .plain, target: self, action: #selector(importTapped))
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DetailCell")
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func doneTapped() {
        dismiss(animated: true)
    }
    
    @objc private func importTapped() {
        delegate?.worldDirectoryDetail(self, didRequestImport: worldEntry)
    }
}

// MARK: - WorldDirectoryDetailViewController DataSource

extension WorldDirectoryDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3 // Connection info
        case 1: return 3 // World info
        case 2: return 1 // Description
        default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath)
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cell.textLabel?.textColor = ThemeManager.shared.currentTheme.fontColor
        cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.7)
        cell.selectionStyle = .none
        
        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Hostname"
                cell.detailTextLabel?.text = worldEntry.hostname
            case 1:
                cell.textLabel?.text = "Port"
                cell.detailTextLabel?.text = "\(worldEntry.port)"
            case 2:
                cell.textLabel?.text = "Players"
                cell.detailTextLabel?.text = worldEntry.playerCount
            default: break
            }
            
        case 1:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Theme"
                cell.detailTextLabel?.text = worldEntry.theme
            case 1:
                cell.textLabel?.text = "Codebase"
                cell.detailTextLabel?.text = worldEntry.codebase
            case 2:
                cell.textLabel?.text = "Website"
                cell.detailTextLabel?.text = worldEntry.website
                cell.accessoryType = .disclosureIndicator
            default: break
            }
            
        case 2:
            cell.textLabel?.text = "Description"
            cell.detailTextLabel?.text = worldEntry.description
            cell.detailTextLabel?.numberOfLines = 0
            
        default: break
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Connection"
        case 1: return "World Information"
        case 2: return "About"
        default: return nil
        }
    }
}

class WorldOrganizerViewController: UIViewController {
    
    private var worlds: [World]
    weak var delegate: WorldOrganizerDelegate?
    private var tableView: UITableView!
    private var selectedWorlds: Set<Int> = []
    private var isSelectionMode = false
    
    init(worlds: [World]) {
        self.worlds = worlds
        super.init(nibName: nil, bundle: nil)
        title = "Organize Worlds"
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
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Select",
            style: .plain,
            target: self,
            action: #selector(toggleSelectionMode)
        )
        
        // Setup table view
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        tableView.isEditing = false
        tableView.allowsMultipleSelection = false
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WorldOrganizerCell")
        
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
        let favoriteButton = UIBarButtonItem(title: "⭐ Favorite", style: .plain, target: self, action: #selector(favoriteSelected))
        let unfavoriteButton = UIBarButtonItem(title: "☆ Unfavorite", style: .plain, target: self, action: #selector(unfavoriteSelected))
        let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(deleteSelected))
        
        toolbar.setItems([favoriteButton, flexSpace, unfavoriteButton, flexSpace, deleteButton], animated: false)
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
    
    @objc private func doneButtonTapped() {
        delegate?.worldOrganizerDidUpdateWorlds(self)
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
            selectedWorlds.removeAll()
        }
        
        tableView.reloadData()
    }
    
    @objc private func favoriteSelected() {
        performBulkOperation { world in
            world.isFavorite = true
        }
    }
    
    @objc private func unfavoriteSelected() {
        performBulkOperation { world in
            world.isFavorite = false
        }
    }
    
    @objc private func deleteSelected() {
        let alert = UIAlertController(
            title: "Delete Worlds",
            message: "Are you sure you want to delete \(selectedWorlds.count) world(s)? This will also delete all associated automation (triggers, aliases, etc.).",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.performBulkDeletion()
        })
        
        present(alert, animated: true)
    }
    
    private func performBulkOperation(_ operation: (World) -> Void) {
        let context = PersistenceController.shared.viewContext
        
        for index in selectedWorlds {
            if index < worlds.count {
                operation(worlds[index])
            }
        }
        
        do {
            try context.save()
            selectedWorlds.removeAll()
            tableView.reloadData()
        } catch {
            showAlert(title: "Error", message: "Failed to update worlds: \(error.localizedDescription)")
        }
    }
    
    private func performBulkDeletion() {
        let context = PersistenceController.shared.viewContext
        let sortedIndices = selectedWorlds.sorted(by: >)
        
        for index in sortedIndices {
            if index < worlds.count {
                let world = worlds[index]
                context.delete(world)
                worlds.remove(at: index)
            }
        }
        
        do {
            try context.save()
            tableView.reloadData()
            selectedWorlds.removeAll()
        } catch {
            showAlert(title: "Error", message: "Failed to delete worlds: \(error.localizedDescription)")
        }
    }
    
    private func showAlert(title: String, message: String) {
        ErrorPresenter.showError(title: title, message: message)
    }
}

// MARK: - UITableViewDataSource

extension WorldOrganizerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return worlds.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WorldOrganizerCell", for: indexPath)
        let world = worlds[indexPath.row]
        
        let favoriteIcon = world.isFavorite ? "⭐" : ""
        cell.textLabel?.text = "\(favoriteIcon) \(world.name ?? "Unnamed World")"
        cell.detailTextLabel?.text = "\(world.hostname ?? ""):\(world.port)"
        
        cell.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        cell.textLabel?.textColor = ThemeManager.shared.currentTheme.fontColor
        cell.detailTextLabel?.textColor = ThemeManager.shared.currentTheme.fontColor.withAlphaComponent(0.7)
        
        // Show selection state
        if selectedWorlds.contains(indexPath.row) {
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
        let movedWorld = worlds.remove(at: sourceIndexPath.row)
        worlds.insert(movedWorld, at: destinationIndexPath.row)
        
        // Update selection indices after move
        var newSelectedWorlds: Set<Int> = []
        for index in selectedWorlds {
            if index == sourceIndexPath.row {
                newSelectedWorlds.insert(destinationIndexPath.row)
            } else if index < sourceIndexPath.row && index >= destinationIndexPath.row {
                newSelectedWorlds.insert(index + 1)
            } else if index > sourceIndexPath.row && index <= destinationIndexPath.row {
                newSelectedWorlds.insert(index - 1)
            } else {
                newSelectedWorlds.insert(index)
            }
        }
        selectedWorlds = newSelectedWorlds
    }
}

// MARK: - UITableViewDelegate

extension WorldOrganizerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isSelectionMode {
            selectedWorlds.insert(indexPath.row)
            tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isSelectionMode {
            selectedWorlds.remove(indexPath.row)
            tableView.cellForRow(at: indexPath)?.accessoryType = .none
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "All Worlds (\(worlds.count) total)"
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if isSelectionMode {
            return "Select worlds for bulk operations. Drag to reorder."
        } else {
            return "Tap 'Select' for bulk operations and reordering."
        }
    }
} 