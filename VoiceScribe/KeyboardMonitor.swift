import Foundation
import Cocoa
import Carbon

class KeyboardMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyPressed = false
    private var pressedKeyCode: UInt16 = 0

    private let appState = AppState.shared

    init() {}

    func start() {
        // Check accessibility permissions without prompting —
        // the user can grant via Settings > Shortcuts when ready.
        let trusted = AXIsProcessTrusted()

        if !trusted {
            print("Accessibility permissions not granted. User can enable from Settings.")
            DispatchQueue.main.async {
                self.appState.accessibilityDenied = true
            }
            return
        }

        DispatchQueue.main.async {
            self.appState.accessibilityDenied = false
        }
        setupEventTap()
    }

    /// Request accessibility with the system prompt (called explicitly by user action only)
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Poll until permission is granted (background, no re-prompting)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for _ in 0..<120 {
                if AXIsProcessTrusted() {
                    print("Accessibility permission granted!")
                    DispatchQueue.main.async {
                        self?.appState.accessibilityDenied = false
                        self?.setupEventTap()
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 1.0)
            }
            print("Accessibility permission polling timed out.")
        }
    }

    private func setupEventTap() {
        // Create event tap for key events
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue)

        // Store self reference for callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let eventTap = eventTap else {
            print("Failed to create event tap. Make sure accessibility permissions are granted.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("Keyboard monitor started")
            DispatchQueue.main.async {
                self.appState.keyboardMonitorActive = true
            }
        }
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        print("Keyboard monitor stopped")
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle special event types
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Re-enable the tap
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Check for flags changed (modifier keys)
        if type == .flagsChanged {
            let flags = event.flags
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

            // First: handle release of whatever key started the press (regardless of current setting).
            // This prevents isKeyPressed from getting stuck if the shortcut key is changed mid-press.
            if isKeyPressed && keyCode == pressedKeyCode {
                var keyReleased = false
                switch keyCode {
                case 63: // Fn
                    keyReleased = !flags.contains(.maskSecondaryFn)
                case 61: // Right Option
                    keyReleased = !flags.contains(.maskAlternate)
                case 54: // Right Command
                    keyReleased = !flags.contains(.maskCommand)
                default:
                    break
                }

                if keyReleased {
                    isKeyPressed = false
                    pressedKeyCode = 0
                    DispatchQueue.main.async {
                        self.onKeyUp?()
                    }
                    return Unmanaged.passUnretained(event)
                }
            }

            // Then: handle new key presses based on current shortcut setting

            // Handle Globe/Fn key (key code 63 / 0x3F)
            if appState.shortcutKey == .globe || appState.shortcutKey == .fn {
                if keyCode == 63 {  // Fn key
                    let fnPressed = flags.contains(.maskSecondaryFn)

                    if fnPressed && !isKeyPressed {
                        isKeyPressed = true
                        pressedKeyCode = keyCode
                        DispatchQueue.main.async {
                            self.onKeyDown?()
                        }
                    }

                    // Consume the Globe/Fn event so macOS doesn't open emoji picker
                    return nil
                }
            }

            // Handle Right Option
            if appState.shortcutKey == .rightOption {
                if keyCode == 61 {  // Right Option key code
                    let optionPressed = flags.contains(.maskAlternate)

                    if optionPressed && !isKeyPressed {
                        isKeyPressed = true
                        pressedKeyCode = keyCode
                        DispatchQueue.main.async {
                            self.onKeyDown?()
                        }
                    }
                }
            }

            // Handle Right Command
            if appState.shortcutKey == .rightCommand {
                if keyCode == 54 {  // Right Command key code
                    let cmdPressed = flags.contains(.maskCommand)

                    if cmdPressed && !isKeyPressed {
                        isKeyPressed = true
                        pressedKeyCode = keyCode
                        DispatchQueue.main.async {
                            self.onKeyDown?()
                        }
                    }
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}
