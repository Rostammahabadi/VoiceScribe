import Foundation
import Cocoa
import Carbon

class KeyboardMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyPressed = false
    private var accessibilityTimer: Timer?

    private let appState = AppState.shared

    init() {}

    func start() {
        if AXIsProcessTrusted() {
            setupEventTap()
        } else {
            print("Accessibility permissions required — waiting for user to grant access")
            // Poll until the user grants permission via System Settings
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.accessibilityTimer = nil
                    print("Accessibility permission granted, starting keyboard monitor")
                    self?.setupEventTap()
                }
            }
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
        }
    }

    func stop() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil

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
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Handle Globe/Fn key (key code 63 / 0x3F)
            if appState.shortcutKey == .globe || appState.shortcutKey == .fn {
                if keyCode == 63 {  // Fn key
                    let fnPressed = flags.contains(.maskSecondaryFn)

                    if fnPressed && !isKeyPressed {
                        isKeyPressed = true
                        DispatchQueue.main.async {
                            self.onKeyDown?()
                        }
                    } else if !fnPressed && isKeyPressed {
                        isKeyPressed = false
                        DispatchQueue.main.async {
                            self.onKeyUp?()
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
                        DispatchQueue.main.async {
                            self.onKeyDown?()
                        }
                    } else if !optionPressed && isKeyPressed {
                        isKeyPressed = false
                        DispatchQueue.main.async {
                            self.onKeyUp?()
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
                        DispatchQueue.main.async {
                            self.onKeyDown?()
                        }
                    } else if !cmdPressed && isKeyPressed {
                        isKeyPressed = false
                        DispatchQueue.main.async {
                            self.onKeyUp?()
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
