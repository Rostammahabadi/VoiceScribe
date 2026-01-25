import Foundation
import AVFoundation
import CoreAudio

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    var onRecordingComplete: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        // Check microphone permission silently - don't auto-prompt
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        if status != .authorized {
            print("Microphone permission status: \(status.rawValue)")
        }
        // Permission will be requested when user first tries to record
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    func startRecording(deviceID: AudioDeviceID? = nil) {
        // Stop any existing recording
        stopRecording()

        do {
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }

            let inputNode = audioEngine.inputNode

            // Create temp file for recording
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "voicescribe_\(UUID().uuidString).wav"
            recordingURL = tempDir.appendingPathComponent(fileName)

            guard let url = recordingURL else { return }

            // Get the input format
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Create audio file with the same format
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            audioFile = try AVAudioFile(forWriting: url, settings: settings)

            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
                do {
                    try self?.audioFile?.write(from: buffer)
                } catch {
                    print("Error writing audio buffer: \(error)")
                }
            }

            // Start the engine
            try audioEngine.start()
            print("Recording started")

        } catch {
            print("Error starting recording: \(error)")
            onError?(error)
        }
    }

    func stopRecording() {
        guard let audioEngine = audioEngine else { return }

        // Remove tap and stop engine
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        // Close audio file
        audioFile = nil
        self.audioEngine = nil

        // Notify completion
        if let url = recordingURL {
            print("Recording stopped, file saved to: \(url.path)")
            onRecordingComplete?(url)
        }

        recordingURL = nil
    }

    func isRecording() -> Bool {
        return audioEngine?.isRunning ?? false
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
