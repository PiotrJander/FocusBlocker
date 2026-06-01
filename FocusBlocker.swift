// FocusBlocker.swift
//
// Build:
//   swiftc FocusBlocker.swift -o FocusBlocker -framework AppKit -framework Carbon
//
// Run:
//   ./FocusBlocker
//
// Hotkey:
//   Control-Option-Space toggles the window. Change `hotKeyCode` and `hotKeyModifiers`
//   below if that conflicts with another app.
//
// Note:
//   This intentionally avoids UserNotifications because that API expects a real
//   .app bundle. The completion notification uses /usr/bin/osascript instead.

import AppKit
import Carbon

private struct FocusTask {
    let description: String
    let minutes: Int
    let endDate: Date
}

final class FocusBlockerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let hotKeySignature = fourCharCode("FBLK")
    private let hotKeyCode = UInt32(kVK_Space)
    private let hotKeyModifiers = UInt32(controlKey | optionKey)

    private var window: NSWindow!
    private var inputField: NSTextField!
    private var progressLabel: NSTextField!
    private var startButton: NSButton!
    private var cancelButton: NSButton!

    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var cancelMenuItem: NSMenuItem!

    private var timer: Timer?
    private var activeTask: FocusTask?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var hotKeyHandler: EventHandlerUPP?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        buildWindow()
        registerGlobalHotKey()
        showWindow(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Focus timer")
            button.imagePosition = .imageLeading
            button.title = "Focus"
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "No focus block running", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Focus Blocker", action: #selector(showWindow(_:)), keyEquivalent: ""))

        cancelMenuItem = NSMenuItem(title: "Cancel Current Block", action: #selector(cancelCurrentTask(_:)), keyEquivalent: "")
        cancelMenuItem.isEnabled = false
        menu.addItem(cancelMenuItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Focus Blocker"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        let contentView = NSView()
        window.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "What are you focusing on?")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        inputField = NSTextField()
        inputField.placeholderString = "30 minutes review PR X"
        inputField.font = .systemFont(ofSize: 14)
        inputField.target = self
        inputField.action = #selector(startFocusBlock(_:))

        let hintLabel = NSTextField(wrappingLabelWithString: "Type a duration followed by the task. Examples: \"30 minutes review PR X\", \"45m research Y\", \"1 hour write proposal\".")
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)

        progressLabel = NSTextField(labelWithString: "No focus block running.")
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        progressLabel.textColor = .secondaryLabelColor

        startButton = NSButton(title: "Start", target: self, action: #selector(startFocusBlock(_:)))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelCurrentTask(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.isEnabled = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonStack = NSStackView(views: [spacer, cancelButton, startButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        let stack = NSStackView(views: [titleLabel, inputField, hintLabel, progressLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
            inputField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func registerGlobalHotKey() {
        hotKeyHandler = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let app = Unmanaged<FocusBlockerApp>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                app.toggleWindow()
            }

            return noErr
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let hotKeyHandler else {
            return
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            userData,
            &hotKeyHandlerRef
        )

        guard handlerStatus == noErr else {
            print("Could not install hotkey handler: \(handlerStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        let registrationStatus = RegisterEventHotKey(
            hotKeyCode,
            hotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registrationStatus != noErr {
            print("Could not register Control-Option-Space hotkey: \(registrationStatus)")
        }
    }

    @objc private func showWindow(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        inputField.becomeFirstResponder()
    }

    private func toggleWindow() {
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showWindow(nil)
        }
    }

    @objc private func startFocusBlock(_ sender: Any?) {
        let rawInput = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let parsedTask = parseTask(rawInput) else {
            progressLabel.stringValue = "Try something like: 30 minutes review PR X"
            progressLabel.textColor = .systemRed
            NSSound.beep()
            return
        }

        let task = FocusTask(
            description: parsedTask.description,
            minutes: parsedTask.minutes,
            endDate: Date().addingTimeInterval(TimeInterval(parsedTask.minutes * 60))
        )

        timer?.invalidate()

        activeTask = task
        inputField.stringValue = task.description
        progressLabel.textColor = .labelColor
        cancelButton.isEnabled = true
        cancelMenuItem.isEnabled = true

        updateDisplayedTask()

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.updateDisplayedTask()
        }

        window.orderOut(nil)
    }

    @objc private func cancelCurrentTask(_ sender: Any?) {
        timer?.invalidate()
        timer = nil
        activeTask = nil

        progressLabel.stringValue = "No focus block running."
        progressLabel.textColor = .secondaryLabelColor
        cancelButton.isEnabled = false
        cancelMenuItem.isEnabled = false
        updateStatusItem(title: "Focus", menuText: "No focus block running")
    }

    private func updateDisplayedTask() {
        guard let task = activeTask else {
            return
        }

        let remainingSeconds = task.endDate.timeIntervalSinceNow

        if remainingSeconds <= 0 {
            finishTask(task)
            return
        }

        let remainingMinutes = max(1, Int(ceil(remainingSeconds / 60)))
        let statusText = "\(remainingMinutes)m \(task.description)"
        progressLabel.stringValue = "\(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s") left: \(task.description)"
        progressLabel.textColor = .labelColor
        updateStatusItem(title: shortened(statusText, limit: 34), menuText: statusText)
    }

    private func finishTask(_ task: FocusTask) {
        timer?.invalidate()
        timer = nil
        activeTask = nil

        progressLabel.stringValue = "Time's up: \(task.description)"
        progressLabel.textColor = .labelColor
        cancelButton.isEnabled = false
        cancelMenuItem.isEnabled = false
        updateStatusItem(title: "Done", menuText: "Done: \(task.description)")

        NSSound.beep()
        sendCompletionNotification(for: task)
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func updateStatusItem(title: String, menuText: String) {
        statusItem.button?.title = title
        statusMenuItem.title = menuText
    }

    private func sendCompletionNotification(for task: FocusTask) {
        let title = appleScriptString("Focus block complete")
        let body = appleScriptString("Time to choose a new task. Finished: \(task.description)")
        let script = "display notification \(body) with title \(title) sound name \"Glass\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
        } catch {
            print("Could not send notification via osascript: \(error)")
        }
    }

    private func appleScriptString(_ value: String) -> String {
        let escapedValue = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")

        return "\"\(escapedValue)\""
    }

    private func parseTask(_ input: String) -> (minutes: Int, description: String)? {
        let pattern = #"^\s*(\d+)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours)?\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = regex.firstMatch(in: input, range: range), match.numberOfRanges == 4 else {
            return nil
        }

        guard
            let amountRange = Range(match.range(at: 1), in: input),
            let amount = Int(input[amountRange]),
            amount > 0,
            let descriptionRange = Range(match.range(at: 3), in: input)
        else {
            return nil
        }

        let unit: String
        if let unitRange = Range(match.range(at: 2), in: input) {
            unit = String(input[unitRange]).lowercased()
        } else {
            unit = "minutes"
        }

        let multiplier = unit.hasPrefix("h") ? 60 : 1
        let description = String(input[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !description.isEmpty else {
            return nil
        }

        return (minutes: amount * multiplier, description: description)
    }

    private func shortened(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let prefixLength = max(0, limit - 3)
        return String(text.prefix(prefixLength)) + "..."
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.prefix(4).reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}

let app = NSApplication.shared
let delegate = FocusBlockerApp()
app.delegate = delegate
app.run()
