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
    static var shared: AppDelegate?

    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    var appState = AppState.shared
    var keyboardMonitor: KeyboardMonitor?
    var audioRecorder: AudioRecorder?
    var transcriptionService: TranscriptionService?
    var pythonProcess: Process?
    var settingsWindow: NSWindow?
    var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Prevent macOS from auto-terminating this background app
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("VoiceScribe is a persistent menu bar app")

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
        keyboardMonitor?.stop()
        if let process = pythonProcess, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "VoiceScribe")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        let newPopover = NSPopover()
        newPopover.contentSize = NSSize(width: 320, height: 400)
        newPopover.behavior = .transient
        newPopover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
        )
        popover = newPopover
    }

    private func setupServices() {
        audioRecorder = AudioRecorder()
        transcriptionService = TranscriptionService()

        // Observe recording state
        audioRecorder?.onRecordingComplete = { [weak self] audioURL in
            self?.handleRecordingComplete(audioURL: audioURL)
        }

        // Pre-warm: request mic permission early so engine is ready before first key press
        audioRecorder?.requestMicrophonePermission { granted in
            if granted {
                print("Microphone permission granted, audio engine pre-warmed")
            }
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

        // Get the script path - check multiple locations
        let resourcePath = Bundle.main.resourcePath ?? ""
        let bundleScriptPath = resourcePath + "/transcription_server.py"
        let siblingScriptPath = Bundle.main.bundlePath
            .replacingOccurrences(of: "/VoiceScribe.app", with: "")
            + "/transcription_server.py"
        let devScriptPath = FileManager.default.currentDirectoryPath + "/transcription_server.py"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let installedScriptPath = "\(home)/.voicescribe/transcription_server.py"

        var finalScriptPath: String? = nil

        // 1. Check installed location (~/.voicescribe/)
        if FileManager.default.fileExists(atPath: installedScriptPath) {
            finalScriptPath = installedScriptPath
        }
        // 2. Check inside the app bundle (distributed builds)
        else if FileManager.default.fileExists(atPath: bundleScriptPath) {
            finalScriptPath = bundleScriptPath
        }
        // 3. Check next to the .app (sibling)
        else if FileManager.default.fileExists(atPath: siblingScriptPath) {
            finalScriptPath = siblingScriptPath
        }
        // 4. Check CWD (running from terminal in project dir)
        else if FileManager.default.fileExists(atPath: devScriptPath) {
            finalScriptPath = devScriptPath
        }
        // 5. Walk up from the .app bundle to find project root
        else {
            var searchDir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
            for _ in 0..<5 {
                let candidate = searchDir.appendingPathComponent("transcription_server.py").path
                if FileManager.default.fileExists(atPath: candidate) {
                    finalScriptPath = candidate
                    break
                }
                let parent = searchDir.deletingLastPathComponent()
                if parent.path == searchDir.path { break }
                searchDir = parent
            }
        }

        guard let scriptPath = finalScriptPath else {
            DispatchQueue.main.async {
                self.appState.serverStatus = .error("transcription_server.py not found")
            }
            return
        }

        // Find Python executable — check venv locations, then system
        var venvCandidates: [String] = []

        // Installed venv
        venvCandidates.append("\(home)/.voicescribe/venv/bin/python3")

        // Venv next to the script
        let scriptDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent().path
        venvCandidates.append(scriptDir + "/venv/bin/python3")

        // Walk up from bundle to find project root venv
        var searchDir = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = searchDir.appendingPathComponent("venv/bin/python3").path
            if !venvCandidates.contains(candidate) {
                venvCandidates.append(candidate)
            }
            let parent = searchDir.deletingLastPathComponent()
            if parent.path == searchDir.path { break }
            searchDir = parent
        }

        // Common project locations
        for projectName in ["VoiceScribe", "voicescribe"] {
            venvCandidates.append(home + "/\(projectName)/venv/bin/python3")
            venvCandidates.append(home + "/Projects/\(projectName)/venv/bin/python3")
            venvCandidates.append(home + "/Developer/\(projectName)/venv/bin/python3")
            venvCandidates.append(home + "/src/\(projectName)/venv/bin/python3")
        }

        let pythonPaths = venvCandidates + [
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

        print("Using Python at: \(python)")
        print("Using Python script at: \(scriptPath)")

        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [scriptPath]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — Python process exited. Nil out handler to stop CPU spin.
                handle.readabilityHandler = nil
                return
            }
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

            // Poll health until server is ready, then monitor periodically
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startHealthCheckPolling()
            }
        } catch {
            DispatchQueue.main.async {
                self.appState.serverStatus = .error(error.localizedDescription)
            }
        }
    }

    // Retry health check until server is ready (up to 2 minutes)
    private func startHealthCheckPolling(attempt: Int = 0) {
        guard attempt < 60 else {
            DispatchQueue.main.async {
                self.appState.serverStatus = .error("Server failed to start after 2 minutes")
            }
            return
        }

        transcriptionService?.checkHealth { [weak self] isHealthy, modelLoaded in
            DispatchQueue.main.async {
                if isHealthy {
                    self?.appState.serverStatus = modelLoaded ? .ready : .loadingModel
                    self?.appState.modelLoaded = modelLoaded
                    if modelLoaded {
                        // Server ready — start periodic monitoring
                        self?.startPeriodicHealthMonitoring()
                    } else {
                        // Model still loading, keep polling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self?.startHealthCheckPolling(attempt: attempt + 1)
                        }
                    }
                } else {
                    // Server not yet reachable, retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.startHealthCheckPolling(attempt: attempt + 1)
                    }
                }
            }
        }
    }

    // Periodic health monitoring after server is ready
    private func startPeriodicHealthMonitoring() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.transcriptionService?.checkHealth { isHealthy, modelLoaded in
                DispatchQueue.main.async {
                    if isHealthy {
                        self?.appState.serverStatus = modelLoaded ? .ready : .loadingModel
                        self?.appState.modelLoaded = modelLoaded
                    } else {
                        self?.appState.serverStatus = .error("Server not responding")
                    }
                    // Continue monitoring
                    self?.startPeriodicHealthMonitoring()
                }
            }
        }
    }

    @objc func togglePopover() {
        guard let button = statusBarItem?.button, let popover = popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)

            // Monitor for clicks outside the popover to dismiss it
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    func startRecording() {
        guard appState.serverStatus == .ready else {
            print("Server not ready")
            return
        }

        appState.isRecording = true
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
        let cleanup = appState.textCleanupEnabled
        transcriptionService?.transcribe(audioURL: audioURL, cleanup: cleanup) { [weak self] result in
            DispatchQueue.main.async {
                self?.appState.isTranscribing = false

                switch result {
                case .success(let text):
                    self?.appState.lastTranscription = text
                    // Add to transcription history
                    self?.appState.addTranscription(text)

                    // Only copy to clipboard if autoCopy is enabled
                    if self?.appState.autoCopyEnabled == true {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }

                    // Type text if enabled
                    if self?.appState.autoTypeEnabled == true {
                        if self?.appState.autoCopyEnabled != true {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        self?.typeText(text)
                    }

                case .failure(let error):
                    self?.appState.lastTranscription = "Error: \(error.localizedDescription)"
                }
            }

            // Clean up temp file off the main thread
            DispatchQueue.global(qos: .utility).async {
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }

    private func typeText(_ text: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.15)

            let source = CGEventSource(stateID: .combinedSessionState)
            source?.localEventsSuppressionInterval = 0.0

            let vKeyCode: CGKeyCode = 9

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
                print("Failed to create keyDown event")
                return
            }
            keyDown.flags = [.maskCommand]

            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
                print("Failed to create keyUp event")
                return
            }
            keyUp.flags = [.maskCommand]

            keyDown.post(tap: .cgAnnotatedSessionEventTap)
            Thread.sleep(forTimeInterval: 0.05)
            keyUp.post(tap: .cgAnnotatedSessionEventTap)

            print("Paste command sent via CGEvent")
        }
    }

    private func updateStatusBarIcon(recording: Bool) {
        DispatchQueue.main.async {
            if let button = self.statusBarItem?.button {
                let symbolName = recording ? "waveform.circle.fill" : "waveform.circle"
                button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VoiceScribe")
                button.image?.isTemplate = true
            }
        }
    }
}
