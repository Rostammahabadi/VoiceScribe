import SwiftUI
import AppKit

@main
struct VoiceScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var appState = AppState.shared
    var keyboardMonitor: KeyboardMonitor?
    var audioRecorder: AudioRecorder?
    var transcriptionService: TranscriptionService?
    var pythonProcess: Process?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Setup components
        setupStatusBar()
        setupServices()
        setupKeyboardMonitor()

        // Start Python transcription server
        startTranscriptionServer()
    }

    func openSettingsWindow() {
        // Close popover first
        popover?.performClose(nil)

        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(appState)

            let hostingController = NSHostingController(rootView: settingsView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "VoiceScribe Settings"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 550, height: 420))
            window.minSize = NSSize(width: 400, height: 300)
            window.center()

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up Python process
        pythonProcess?.terminate()
        keyboardMonitor?.stop()
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "VoiceScribe")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
        )
    }

    private func setupServices() {
        audioRecorder = AudioRecorder()
        transcriptionService = TranscriptionService()

        // Observe recording state
        audioRecorder?.onRecordingComplete = { [weak self] audioURL in
            self?.handleRecordingComplete(audioURL: audioURL)
        }
    }

    private func setupKeyboardMonitor() {
        keyboardMonitor = KeyboardMonitor()
        keyboardMonitor?.onKeyDown = { [weak self] in
            self?.startRecording()
        }
        keyboardMonitor?.onKeyUp = { [weak self] in
            self?.stopRecording()
        }
        keyboardMonitor?.start()
    }

    private func startTranscriptionServer() {
        appState.serverStatus = .starting

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.launchPythonServer()
        }
    }

    private func launchPythonServer() {
        let process = Process()
        pythonProcess = process

        // Find Python executable
        let pythonPaths = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]

        var pythonPath: String?
        for path in pythonPaths {
            if FileManager.default.fileExists(atPath: path) {
                pythonPath = path
                break
            }
        }

        guard let python = pythonPath else {
            DispatchQueue.main.async {
                self.appState.serverStatus = .error("Python not found")
            }
            return
        }

        // Get the script path - check multiple locations
        let resourcePath = Bundle.main.resourcePath ?? ""
        let bundleScriptPath = resourcePath + "/transcription_server.py"
        let siblingScriptPath = Bundle.main.bundlePath
            .replacingOccurrences(of: "/VoiceScribe.app", with: "")
            + "/transcription_server.py"
        let devScriptPath = FileManager.default.currentDirectoryPath + "/transcription_server.py"

        var finalScriptPath = devScriptPath
        if FileManager.default.fileExists(atPath: bundleScriptPath) {
            finalScriptPath = bundleScriptPath
        } else if FileManager.default.fileExists(atPath: siblingScriptPath) {
            finalScriptPath = siblingScriptPath
        }

        print("Using Python script at: \(finalScriptPath)")

        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [finalScriptPath]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("[Python] \(output)")

                if output.contains("loaded successfully") {
                    DispatchQueue.main.async {
                        self?.appState.serverStatus = .ready
                        self?.appState.modelLoaded = true
                    }
                }
            }
        }

        do {
            try process.run()

            // Wait a moment then check health
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.checkServerHealth()
            }
        } catch {
            DispatchQueue.main.async {
                self.appState.serverStatus = .error(error.localizedDescription)
            }
        }
    }

    private func checkServerHealth() {
        transcriptionService?.checkHealth { [weak self] isHealthy, modelLoaded in
            DispatchQueue.main.async {
                if isHealthy {
                    self?.appState.serverStatus = modelLoaded ? .ready : .loadingModel
                    self?.appState.modelLoaded = modelLoaded
                }
            }
        }
    }

    @objc func togglePopover() {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func startRecording() {
        guard appState.serverStatus == .ready else {
            print("Server not ready")
            return
        }

        DispatchQueue.main.async {
            self.appState.isRecording = true
        }

        audioRecorder?.startRecording(deviceID: appState.selectedInputDevice)
        updateStatusBarIcon(recording: true)
    }

    func stopRecording() {
        audioRecorder?.stopRecording()
        updateStatusBarIcon(recording: false)

        DispatchQueue.main.async {
            self.appState.isRecording = false
            self.appState.isTranscribing = true
        }
    }

    private func handleRecordingComplete(audioURL: URL) {
        transcriptionService?.transcribe(audioURL: audioURL) { [weak self] result in
            DispatchQueue.main.async {
                self?.appState.isTranscribing = false

                switch result {
                case .success(let text):
                    self?.appState.lastTranscription = text
                    // Copy to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)

                    // Type text if enabled
                    if self?.appState.autoTypeEnabled == true {
                        self?.typeText(text)
                    }

                case .failure(let error):
                    self?.appState.lastTranscription = "Error: \(error.localizedDescription)"
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }

    private func typeText(_ text: String) {
        // Text is already on clipboard, simulate Cmd+V to paste using CGEvent
        // Run on background thread with delay to ensure focus is restored
        DispatchQueue.global(qos: .userInitiated).async {
            // Wait for any UI updates and focus restoration
            Thread.sleep(forTimeInterval: 0.15)

            let source = CGEventSource(stateID: .combinedSessionState)
            source?.localEventsSuppressionInterval = 0.0

            // 'v' key code is 9
            let vKeyCode: CGKeyCode = 9

            // Create key down event with Command modifier
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
                print("Failed to create keyDown event")
                return
            }
            keyDown.flags = [.maskCommand]

            // Create key up event with Command modifier
            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
                print("Failed to create keyUp event")
                return
            }
            keyUp.flags = [.maskCommand]

            // Post events to the HID event tap (works globally)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.05)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)

            print("Paste command sent via CGEvent")
        }
    }

    private func updateStatusBarIcon(recording: Bool) {
        DispatchQueue.main.async {
            if let button = self.statusBarItem.button {
                let symbolName = recording ? "waveform.circle.fill" : "waveform.circle"
                button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VoiceScribe")
                button.image?.isTemplate = true
            }
        }
    }
}
