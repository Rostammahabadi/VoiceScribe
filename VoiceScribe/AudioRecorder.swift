import Foundation
import AVFoundation
import CoreAudio

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var isCapturing = false
    private var engineReady = false
    private var micPermissionGranted = false
    private var cachedFormat: AVAudioFormat?
    private let recordingLock = NSLock()

    var onRecordingComplete: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        super.init()
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if micPermissionGranted {
            completion(true)
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            micPermissionGranted = true
            prepareEngine()
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    self?.micPermissionGranted = true
                    self?.prepareEngine()
                }
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    /// Pre-warms the audio engine so recording starts instantly on key press.
    /// Creates the engine, installs the tap, and prepares hardware — but does NOT start.
    func prepareEngine() {
        guard !engineReady else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        cachedFormat = inputFormat

        // Install a persistent tap that writes when isCapturing is true
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recordingLock.lock()
            let capturing = self.isCapturing
            let file = self.audioFile
            self.recordingLock.unlock()

            guard capturing, let file = file else { return }
            do {
                try file.write(from: buffer)
            } catch {
                print("Error writing audio buffer: \(error)")
            }
        }

        // Prepare pre-allocates audio hardware resources (fast start later)
        engine.prepare()
        audioEngine = engine
        engineReady = true
        print("Audio engine prepared and ready")
    }

    func startRecording(deviceID: AudioDeviceID? = nil) {
        if !engineReady {
            prepareEngine()
        }

        guard let engine = audioEngine else {
            print("No audio engine available")
            return
        }

        // Start engine (fast after prepare/pause)
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Error starting audio engine: \(error)")
                // Try full reset
                engineReady = false
                prepareEngine()
                guard let engine = audioEngine else { return }
                do { try engine.start() } catch {
                    print("Failed to start audio engine after reset: \(error)")
                    onError?(error)
                    return
                }
            }
        }

        let inputFormat = cachedFormat ?? engine.inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voicescribe_\(UUID().uuidString).wav"
        let url = tempDir.appendingPathComponent(fileName)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)

            recordingLock.lock()
            recordingURL = url
            audioFile = file
            isCapturing = true
            recordingLock.unlock()

            print("Recording started")
        } catch {
            print("Error creating audio file: \(error)")
            onError?(error)
        }
    }

    func stopRecording() {
        recordingLock.lock()
        isCapturing = false
        audioFile = nil  // closes the file
        let url = recordingURL
        recordingURL = nil
        recordingLock.unlock()

        // Pause engine (keeps it prepared for fast restart, releases mic indicator)
        audioEngine?.pause()

        // Notify completion
        if let url = url {
            print("Recording stopped, file saved to: \(url.path)")
            onRecordingComplete?(url)
        }
    }

    func isRecording() -> Bool {
        recordingLock.lock()
        let capturing = isCapturing
        recordingLock.unlock()
        return capturing
    }
}

// Extension for setting input device (requires CoreAudio)
extension AudioRecorder {
    func setInputDevice(_ deviceID: AudioDeviceID) {
        // Note: AVAudioEngine uses the system default input device
        // To change the input device, we'd need to use a lower-level API
        // For now, users should set their preferred input in System Preferences

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDCopy = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            propertySize,
            &deviceIDCopy
        )

        if status != noErr {
            print("Failed to set input device: \(status)")
        }
    }
}
