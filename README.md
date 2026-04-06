# VoiceScribe

A native macOS menu bar app for speech-to-text transcription, powered by local AI. Hold a key, speak, release — your words appear instantly wherever your cursor is.

Built with Swift and [MLX Audio](https://github.com/Blaizzy/mlx-audio), optimized for Apple Silicon. All processing happens on-device.

## Requirements

- **Apple Silicon** Mac (M1, M2, M3, M4, or later)
- **macOS 13.0+**
- **Python 3.9+** (`python3 --version` to check; install with `brew install python3` if needed)
- **Xcode Command Line Tools** (`xcode-select --install` if not already installed)
- ~2GB free disk space (for the AI model, downloaded on first run)

## Installation

### Download Release

1. Download the latest release from [Releases](../../releases)
2. Unzip, open Terminal, type `bash `, drag `install.sh` into Terminal, and press Enter

That's it. The installer checks your system, sets up a Python virtual environment at `~/.voicescribe/`, installs dependencies, copies the app to `/Applications`, and launches it.

### Build from Source

```bash
git clone https://github.com/Rostammahabadi/VoiceScribe.git
cd VoiceScribe
chmod +x setup.sh run.sh
./setup.sh
```

This single script will:
1. Verify prerequisites (Apple Silicon, Python, Xcode tools)
2. Create a Python virtual environment and install `mlx-audio`
3. Build the app with `xcodebuild`
4. Install `VoiceScribe.app` to `/Applications`

When it finishes, launch with:

```bash
open /Applications/VoiceScribe.app
```

Or use the helper script (runs setup if needed, then launches):

```bash
./run.sh
```

## First Launch

On first launch you must grant two permissions:

1. **Accessibility** — Go to Settings > Shortcuts in the app and click "Grant Accessibility Permission". This opens System Settings where you toggle VoiceScribe **ON** in the Accessibility list.

2. **Microphone** — Click "Allow" when prompted.

The app will also download the Parakeet AI model (~1.2GB) on the first run. This takes 30-60 seconds depending on your connection. Subsequent launches use the cached model.

## Usage

1. Look for the **waveform icon** in your menu bar
2. Click in any text field where you want to type
3. **Hold the Right Option key** and speak clearly
4. **Release the key** — your speech is transcribed and pasted automatically

The default shortcut is **Right Option** (right side of keyboard, next to Right Command). You can change this in Settings.

## Settings

Click the menu bar icon, then "Settings" to configure:

| Setting | Description | Default |
|---------|-------------|---------|
| **Push-to-talk key** | Right Option, Right Command, Globe/Fn | Right Option |
| **Input device** | Select from available microphones | System default |
| **Auto-copy** | Copy transcription to clipboard | On |
| **Auto-type** | Paste transcription at cursor | On |
| **Text cleanup** | Remove filler words via local Ollama | On |

> **Globe/Fn key note:** If you select Globe or Fn as your shortcut, you must also change a system setting: **System Settings > Keyboard > "Press Globe key to" > "Do Nothing"**. Otherwise macOS intercepts the key for Emoji/Input Source and VoiceScribe never sees it.

## Architecture

```
VoiceScribe.app (Swift/SwiftUI)
  ├── Menu Bar UI
  ├── Keyboard Monitor (global push-to-talk via CGEvent tap)
  ├── Audio Recorder (AVAudioEngine)
  └── HTTP client ──POST /transcribe──► localhost:8765
                                              │
                                    transcription_server.py
                                    (bundled inside the .app)
                                              │
                                      MLX Audio + Parakeet TDT 0.6B
                                      (on-device speech-to-text)
```

The Python transcription server is bundled inside the app and launched automatically. No separate server setup is needed.

## Troubleshooting

### "Accessibility permission required"
Go to **System Settings > Privacy & Security > Accessibility** and enable VoiceScribe. The app will detect the change automatically.

### Keyboard shortcut not working
1. Verify VoiceScribe is listed and **enabled** in System Settings > Privacy & Security > Accessibility
2. If using Globe/Fn key: set System Settings > Keyboard > "Press Globe key to" > "Do Nothing"
3. Click the menu bar icon — it should say "Hold Right Option to record". If it says "Keyboard monitor inactive", Accessibility permission is missing.
4. Try Right Option or Right Command as the shortcut (these work without extra configuration)

### Microphone permission
Go to **System Settings > Privacy & Security > Microphone** and enable VoiceScribe.

### "Model loading..." takes forever
The first launch downloads a ~1.2GB model. Subsequent launches use the cached model.

### "Server not ready" / transcription not working
1. Click the menu bar icon and check the server status indicator
2. On first launch, wait for the model to finish downloading (~1.2GB)
3. If the status shows an error, quit and relaunch the app
4. Verify Python dependencies: `~/.voicescribe/venv/bin/python3 -c "import mlx_audio; print('OK')"`

### App not appearing in menu bar
VoiceScribe is a menu bar app — it has no dock icon. Look for the waveform icon in the top-right menu bar area.

### 100% CPU usage
Quit VoiceScribe, make sure no old `transcription_server.py` processes are running (`pkill -f transcription_server.py`), then relaunch.

### Intel Mac
VoiceScribe requires Apple Silicon. MLX does not support Intel processors.

### Rebuilding after code changes
```bash
./setup.sh
```
This rebuilds and reinstalls to `/Applications`. Or build manually:
```bash
xcodebuild -project VoiceScribe.xcodeproj -scheme VoiceScribe -configuration Release build SYMROOT=build
rsync -a --delete build/Release/VoiceScribe.app/ /Applications/VoiceScribe.app/
```
Note: use `rsync`, not `cp -R` (which silently fails to overwrite an existing app bundle).

## Development

For development, you can run the transcription server standalone:

```bash
source venv/bin/activate
python3 transcription_server.py
```

The server runs on `localhost:8765`. The app will connect to an already-running server if one exists.

## Privacy

All audio is processed **locally on your device**:
- No audio is sent to external servers
- No transcriptions are stored or transmitted
- No analytics or telemetry

The only network request is to download the AI model from Hugging Face on first launch.

## Tech Stack

- **Swift / SwiftUI** — Native macOS menu bar app
- **MLX Audio** — Apple Silicon-optimized ML inference
- **Parakeet TDT 0.6B** — NVIDIA's speech recognition model
- **Python** — Transcription server backend (bundled inside the app)

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [MLX Audio](https://github.com/Blaizzy/mlx-audio) by Prince Canuma
- [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b) by NVIDIA
- [Apple MLX](https://github.com/ml-explore/mlx)
