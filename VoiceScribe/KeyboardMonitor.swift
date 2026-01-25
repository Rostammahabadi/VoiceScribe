import Foundation
import Cocoa
import Carbon

class KeyboardMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyPressed = false

    private let appState = AppState.shared

    init() {}

    func start() {
        // Check accessibility permissions silently - never prompt automatically
        let trusted = AXIsProcessTrusted()

        if !trusted {
            print("Accessibility permissions required. Please grant access in System Settings > Privacy & Security > Accessibility")
            // Don't auto-prompt - user can enable via Settings if needed
            return
        }

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
            // The Fn key doesn't have a specific flag, but we can detect it via flags changed
            if appState.shortcutKey == .globe || appState.shortcutKey == .fn {
                // Check if this is the Fn key by looking at the event
                // Fn key presses generate flagsChanged events with keycode 63
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
