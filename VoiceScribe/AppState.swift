import Foundation
import AVFoundation
import Combine

enum ServerStatus: Equatable {
    case starting
    case loadingModel
    case ready
    case error(String)

    var description: String {
        switch self {
        case .starting:
            return "Starting server..."
        case .loadingModel:
            return "Loading Parakeet model..."
        case .ready:
            return "Ready"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var serverStatus: ServerStatus = .starting
    @Published var modelLoaded: Bool = false
    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var lastTranscription: String = ""
    @Published var transcriptionHistory: [TranscriptionEntry] = []

    // Settings
    @Published var selectedInputDevice: AudioDeviceID? {
        didSet {
            if let deviceID = selectedInputDevice {
                UserDefaults.standard.set(Int(deviceID), forKey: "selectedInputDevice")
            }
        }
    }
    @Published var shortcutKey: ShortcutKey = .globe {
        didSet {
            UserDefaults.standard.set(shortcutKey.rawValue, forKey: "shortcutKey")
        }
    }
    @Published var autoTypeEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoTypeEnabled, forKey: "autoTypeEnabled")
        }
    }
    @Published var autoCopyEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoCopyEnabled, forKey: "autoCopyEnabled")
        }
    }
    @Published var textCleanupEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(textCleanupEnabled, forKey: "textCleanupEnabled")
        }
    }

    @Published var availableInputDevices: [AudioDevice] = []

    private init() {
        loadSettings()
        refreshInputDevices()
    }

    private func loadSettings() {
        if let savedDevice = UserDefaults.standard.object(forKey: "selectedInputDevice") as? Int {
            selectedInputDevice = AudioDeviceID(savedDevice)
        }

        if let savedShortcut = UserDefaults.standard.string(forKey: "shortcutKey"),
           let shortcut = ShortcutKey(rawValue: savedShortcut) {
            shortcutKey = shortcut
        }

        autoTypeEnabled = UserDefaults.standard.object(forKey: "autoTypeEnabled") as? Bool ?? true
        autoCopyEnabled = UserDefaults.standard.object(forKey: "autoCopyEnabled") as? Bool ?? true
        textCleanupEnabled = UserDefaults.standard.object(forKey: "textCleanupEnabled") as? Bool ?? true
    }

    func refreshInputDevices() {
        availableInputDevices = AudioDeviceManager.getInputDevices()

        // Set default device if none selected
        if selectedInputDevice == nil, let firstDevice = availableInputDevices.first {
            selectedInputDevice = firstDevice.id
        }
    }

    func addTranscription(_ text: String) {
        let entry = TranscriptionEntry(text: text, timestamp: Date())
        transcriptionHistory.insert(entry, at: 0)

        // Keep only last 50 entries
        if transcriptionHistory.count > 50 {
            transcriptionHistory = Array(transcriptionHistory.prefix(50))
        }
    }
}

struct TranscriptionEntry: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

enum ShortcutKey: String, CaseIterable {
    case globe = "globe"
    case fn = "fn"
    case rightOption = "rightOption"
    case rightCommand = "rightCommand"

    var displayName: String {
        switch self {
        case .globe: return "Globe (Fn)"
        case .fn: return "Fn Key"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .globe, .fn: return 0x3F  // Fn key
        case .rightOption: return 0x3D  // Right Option
        case .rightCommand: return 0x36  // Right Command
        }
    }
}

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool
}

class AudioDeviceManager {
    static func getInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []

        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // Get size of device list
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard status == noErr else { return devices }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard status == noErr else { return devices }

        // Get default input device
        var defaultInputDevice: AudioDeviceID = 0
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultInputDevice
        )

        // Filter for input devices and get names
        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var configSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &configSize)

            if status == noErr && configSize > 0 {
                let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPtr.deallocate() }

                status = AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &configSize, bufferListPtr)

                if status == noErr {
                    let bufferList = bufferListPtr.pointee
                    var inputChannels: UInt32 = 0

                    let buffers = UnsafeMutableAudioBufferListPointer(bufferListPtr)
                    for buffer in buffers {
                        inputChannels += buffer.mNumberChannels
                    }

                    if inputChannels > 0 {
                        // Get device name
                        var nameAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyDeviceNameCFString,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )

                        var name: CFString = "" as CFString
                        var nameSize = UInt32(MemoryLayout<CFString>.size)

                        status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)

                        if status == noErr {
                            let device = AudioDevice(
                                id: deviceID,
                                name: name as String,
                                isDefault: deviceID == defaultInputDevice
                            )
                            devices.append(device)
                        }
                    }
                }
            }
        }

        return devices.sorted { $0.isDefault && !$1.isDefault }
    }
}
