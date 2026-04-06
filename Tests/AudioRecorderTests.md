# AudioRecorder Manual Verification Steps

## C2: selectedInputDevice is applied via setInputDevice

### Prerequisites
- macOS system with at least two audio input devices (e.g., built-in microphone and an external USB microphone)

### Steps

1. Open VoiceScribe Settings and navigate to the Audio section.
2. Select a non-default microphone from the input device list.
3. Start a recording using push-to-talk.
4. Speak into the selected (non-default) microphone.
5. Stop the recording and verify the audio was captured from the selected device, not the system default.
6. Change the selected device to a different microphone.
7. Record again and verify audio now comes from the newly selected device.

### Expected Behavior
- `startRecording(deviceID:)` calls `setInputDevice(_:)` before starting the audio engine.
- The system default input device is updated to the selected device via CoreAudio before the engine begins capturing.
- Audio in the resulting file matches the selected input device.

### Edge Cases
- If no deviceID is provided (nil), `setInputDevice` is not called and the current system default is used.
- If the engine was already prepared (pre-warmed), the device change still takes effect because `setInputDevice` updates the system default input device, which AVAudioEngine picks up on start.
