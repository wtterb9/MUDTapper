import UIKit
import CoreData

class TriggerEditorViewController: UIViewController {
    private let world: World
    private var trigger: Trigger?
    var initialPattern: String?
    var onDismiss: (() -> Void)?

    private let patternField = UITextField()
    private let commandsView = UITextView()
    private let infoLabel = UILabel()

    init(world: World, trigger: Trigger? = nil) {
        self.world = world
        self.trigger = trigger
        super.init(nibName: nil, bundle: nil)
        title = trigger == nil ? "➕ New Trigger" : "✏️ Edit Trigger"
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

        patternField.placeholder = "Pattern (e.g., * tells you *)"
        patternField.borderStyle = .roundedRect
        patternField.autocapitalizationType = .none
        patternField.autocorrectionType = .no
        patternField.textColor = ThemeManager.shared.terminalTextColor
        patternField.keyboardAppearance = ThemeManager.shared.isDarkTheme ? .dark : .light

        infoLabel.text = "Tip: Use * and ? for wildcards, or regex."
        infoLabel.textColor = ThemeManager.shared.terminalTextColor.withAlphaComponent(0.7)
        infoLabel.font = UIFont.systemFont(ofSize: 12)

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
        commandsView.heightAnchor.constraint(equalToConstant: 260).isActive = true

        stack.addArrangedSubview(patternField)
        stack.addArrangedSubview(infoLabel)
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
        if let trig = trigger {
            patternField.text = trig.trigger
            if let cmds = trig.commands {
                let lines = cmds.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                commandsView.text = lines.joined(separator: "\n")
            }
        } else if let initialPattern = initialPattern {
            patternField.text = initialPattern
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) { self.onDismiss?() }
    }

    @objc private func saveTapped() {
        let pattern = (patternField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = commandsView.text.split(whereSeparator: { $0.isNewline }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !pattern.isEmpty, !lines.isEmpty else {
            let alert = UIAlertController(title: "Missing Information", message: "Please enter both pattern and commands", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let commands = lines.joined(separator: ";")

        do {
            if let trig = trigger {
                trig.trigger = pattern
                trig.commands = commands
                trig.lastModified = Date()
                try trig.managedObjectContext?.save()
            } else {
                let context = world.managedObjectContext!
                let t = Trigger(context: context)
                t.world = world
                t.trigger = pattern
                t.commands = commands
                t.isHidden = false
                t.lastModified = Date()
                try context.save()
            }
            dismiss(animated: true) { self.onDismiss?() }
        } catch {
            let alert = UIAlertController(title: "Error", message: "Failed to save trigger: \(error.localizedDescription)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}


