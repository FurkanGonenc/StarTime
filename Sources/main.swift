import Cocoa
import ApplicationServices

// MARK: - Views

/// Blurred, translucent background that lets the whole window be dragged.
final class BlurView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Time label that ignores the mouse so drags go to the window.
final class TimeLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var label: TimeLabel!
    private var statusItem: NSStatusItem?
    private var ticker: Timer?
    private var trustPoller: Timer?

    // Stopwatch state
    private var isSessionOpen = false
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?
    private var isRunning: Bool { runningSince != nil }

    // Cmd+Option hotkey state
    private var hotkeyArmed = false
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitIfAlreadyRunning()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshMenuBar),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        installLocalMonitors()
        waitForAccessibilityThenInstallGlobalMonitors()
    }

    // MARK: Single instance

    private func quitIfAlreadyRunning() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty { NSApp.terminate(nil) }
    }

    // MARK: Hotkey

    private func waitForAccessibilityThenInstallGlobalMonitors() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            installGlobalMonitors()
            return
        }
        // Keep checking until the user grants Accessibility access.
        trustPoller = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.installGlobalMonitors()
        }
    }

    private func installGlobalMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.handleFlagsChanged(e.modifierFlags)
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] _ in self?.hotkeyArmed = false }
        ) { monitors.append(m) }
    }

    /// Needed for when our own window is focused (global monitors skip our own events).
    private func installLocalMonitors() {
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            self?.handleFlagsChanged(e.modifierFlags)
            return e
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { [weak self] e in
                self?.hotkeyArmed = false
                return e
            }
        ) { monitors.append(m) }
    }

    /// Fires when Cmd+Option are pressed together and released with no other key
    /// in between, so shortcuts like Cmd+Option+Esc don't toggle the stopwatch.
    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let mods = flags.intersection([.command, .option, .control, .shift])
        if mods == [.command, .option] {
            hotkeyArmed = true
        } else if hotkeyArmed && mods.isSubset(of: [.command, .option]) {
            hotkeyArmed = false
            toggle()
        } else {
            hotkeyArmed = false
        }
    }

    // MARK: Stopwatch

    private var elapsed: TimeInterval {
        accumulated + (runningSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func toggle() {
        if !isSessionOpen {
            isSessionOpen = true
            accumulated = 0
            runningSince = Date()
            showWindow()
            startTicker()
        } else if let since = runningSince {
            accumulated += Date().timeIntervalSince(since)
            runningSince = nil
        } else {
            runningSince = Date()
        }
        updateDisplay()
    }

    private func reset() {
        isSessionOpen = false
        accumulated = 0
        runningSince = nil
        ticker?.invalidate()
        ticker = nil
        removeStatusItem()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.updateDisplay() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func updateDisplay() {
        let text = formatted(elapsed)
        label?.stringValue = text
        label?.textColor = isRunning ? .labelColor : .secondaryLabelColor
        refreshMenuBar()
        statusItem?.button?.appearsDisabled = !isRunning
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 172, height: 72),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "StarTime"
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.standardWindowButton(.zoomButton)?.isHidden = true
        w.delegate = self

        let blur = BlurView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        w.contentView = blur

        label = TimeLabel(labelWithString: "00:00:00")
        label.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: blur.centerYAnchor, constant: 9),
        ])

        w.center()
        return w
    }

    private func showWindow() {
        let w = window ?? makeWindow()
        window = w
        // Show on the current desktop without stealing focus from the user's app.
        w.orderFrontRegardless()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        reset()
        sender.orderOut(nil)
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) { refreshMenuBar() }
    func windowDidDeminiaturize(_ notification: Notification) { refreshMenuBar() }

    // MARK: Menu bar

    /// Shows the time in the menu bar only when the window isn't visible on the current desktop.
    @objc private func refreshMenuBar() {
        guard isSessionOpen, let w = window else { removeStatusItem(); return }
        let visibleHere = w.isVisible && !w.isMiniaturized && w.isOnActiveSpace
        if visibleHere {
            removeStatusItem()
        } else if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            // Masked on purpose: only running/paused shows here, never the actual time.
            item.button?.title = "**:**:**"
            item.button?.appearsDisabled = !isRunning
            statusItem = item
        }
    }

    private func removeStatusItem() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
