import UIKit
import CoreData

class AliasEditorViewController: UIViewController {
    private let world: World
    private var alias: Alias?
    var onDismiss: (() -> Void)?

    private let nameField = UITextField()
    private let commandsView = UITextView()

    init(world: World, alias: Alias? = nil) {
        self.world = world
        self.alias = alias
        super.init(nibName: nil, bundle: nil)
        title = alias == nil ? "➕ New Alias" : "✏️ Edit Alias"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        setupNav()
        setupForm()
        populate()
    }

    private func setupNav() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))
    }

    private func setupForm() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        nameField.placeholder = "Alias name"
        nameField.borderStyle = .roundedRect
        nameField.autocapitalizationType = .none
        nameField.autocorrectionType = .no
        nameField.textColor = ThemeManager.shared.terminalTextColor
        nameField.keyboardAppearance = ThemeManager.shared.isDarkTheme ? .dark : .light

        let commandsLabel = UILabel()
        commandsLabel.text = "Commands (one per line)"
        commandsLabel.textColor = ThemeManager.shared.terminalTextColor

        commandsView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        commandsView.layer.borderWidth = 1
        commandsView.layer.borderColor = UIColor.systemGray4.cgColor
        commandsView.layer.cornerRadius = 8
        commandsView.backgroundColor = ThemeManager.shared.terminalBackgroundColor
        commandsView.textColor = ThemeManager.shared.terminalTextColor
        commandsView.keyboardAppearance = ThemeManager.shared.isDarkTheme ? .dark : .light
        commandsView.heightAnchor.constraint(equalToConstant: 220).isActive = true

        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(commandsLabel)
        stack.addArrangedSubview(commandsView)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func populate() {
        guard let alias = alias else { return }
        nameField.text = alias.name
        // Convert semicolon-separated storage to multi-line for editing
        if let cmds = alias.commands {
            let lines = cmds.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            commandsView.text = lines.joined(separator: "\n")
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { self.onDismiss?() }
    }

    @objc private func saveTapped() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = commandsView.text.split(whereSeparator: { $0.isNewline }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !name.isEmpty, !lines.isEmpty else {
            let alert = UIAlertController(title: "Missing Information", message: "Please fill in both alias name and commands", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let commands = lines.joined(separator: ";")

        do {
            if let alias = alias {
                alias.name = name
                alias.commands = commands
                alias.lastModified = Date()
                try alias.managedObjectContext?.save()
            } else {
                let context = world.managedObjectContext!
                let a = Alias(context: context)
                a.name = name
                a.commands = commands
                a.world = world
                a.isHidden = false
                a.lastModified = Date()
                try context.save()
            }
            dismiss(animated: true) { self.onDismiss?() }
        } catch {
            let alert = UIAlertController(title: "Error", message: "Failed to save alias: \(error.localizedDescription)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}


