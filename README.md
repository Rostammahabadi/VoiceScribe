# VoiceScribe

A native macOS menu bar app for lightning-fast speech-to-text transcription, powered by local AI. Hold a key, speak, release — your words appear instantly wherever your cursor is.

Built with Swift and [MLX Audio](https://github.com/Blaizzy/mlx-audio), optimized for Apple Silicon.

## Features

- **Push-to-Talk** — Hold the Globe (Fn) key to record, release to transcribe
- **Instant Paste** — Transcribed text is automatically pasted at your cursor
- **100% Local** — All processing happens on-device using Apple's MLX framework
- **Menu Bar App** — Lives quietly in your menu bar, always ready
- **Fast & Accurate** — Uses NVIDIA's Parakeet TDT model for high-quality English transcription
- **Configurable** — Choose your microphone, shortcut key, and behavior

## Demo

<!-- Add a GIF or screenshot here -->
![VoiceScribe Menu Bar](https://via.placeholder.com/600x400?text=Add+Screenshot)

## Requirements

- **macOS 13.0** or later
- **Apple Silicon** Mac (M1, M2, M3, or later)
- **Python 3.9+** (for the transcription backend)
- ~2GB disk space (for the AI model, downloaded on first run)

## Installation

### Download Release

1. Download the latest release from [Releases](../../releases)
2. Unzip, open Terminal, type `bash `, drag `install.sh` into Terminal, and press Enter

That's it. The installer checks your system, sets up a Python virtual environment at `~/.voicescribe/`, installs dependencies, copies the app to `/Applications`, and launches it.

### Build from Source

1. **Clone and build**
   ```bash
   git clone https://github.com/Rostammahabadi/VoiceScribe.git
   cd VoiceScribe
   xcodebuild -project VoiceScribe.xcodeproj -scheme VoiceScribe -configuration Release -derivedDataPath build
   ```

2. **Run the installer** (sets up Python venv + dependencies)
   ```bash
   bash dist/VoiceScribe/install.sh
   ```

   The app manages the Python transcription server automatically — no need to start it manually.

## Usage

### Quick Start

1. **Launch VoiceScribe** — Look for the waveform icon in your menu bar
2. **Click in any text field** where you want to type
3. **Hold the Globe (Fn) key** and speak clearly
4. **Release the key** — Your speech is transcribed and pasted automatically

### First Launch

On first launch, VoiceScribe will:
1. Request **Accessibility** permission (for keyboard shortcuts and auto-paste)
2. Request **Microphone** permission (for recording)
3. Download the Parakeet AI model (~1.2GB, cached for future use)

### Menu Bar Options

Click the menu bar icon to access:
- **Status** — See if the transcription server is ready
- **Last Transcription** — View and copy your most recent transcription
- **Input Device** — Select your preferred microphone
- **Settings** — Configure shortcuts and behavior

## Settings

| Setting | Description |
|---------|-------------|
| **Push-to-talk key** | Globe (Fn), Right Option, or Right Command |
| **Input Device** | Select from available microphones |
| **Auto-copy** | Automatically copy transcription to clipboard |
| **Auto-type** | Automatically paste transcription at cursor |

## Architecture

VoiceScribe consists of two components:

```
┌─────────────────────────────────────────────────────────┐
│                    VoiceScribe.app                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Menu Bar  │  │   Audio     │  │    Keyboard     │  │
│  │     UI      │  │  Recorder   │  │    Monitor      │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
│                          │                               │
│                          ▼                               │
│                   HTTP POST /transcribe                  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              transcription_server.py                     │
│  ┌─────────────────────────────────────────────────┐    │
│  │              MLX Audio + Parakeet               │    │
│  │         (Local speech-to-text inference)        │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

- **Swift App**: Handles UI, audio recording, keyboard shortcuts, and clipboard
- **Python Server**: Runs the Parakeet model via MLX Audio on `localhost:8765`

## Troubleshooting

### "Accessibility permission required"
Go to **System Settings → Privacy & Security → Accessibility** and enable VoiceScribe. The app will detect the change automatically.

### Globe (Fn) key doesn't start recording
1. Check Accessibility permission is granted (see above)
2. Make sure server status shows "Ready" in Settings → General
3. If the Globe key opens the emoji picker, go to **System Settings → Keyboard → "Press Globe key to" → "Do Nothing"**
4. Try switching to Right Option in Settings → Shortcuts

### Microphone permission
Go to **System Settings → Privacy & Security → Microphone** and enable VoiceScribe.

### "Model loading..." takes forever
The first launch downloads a ~1.2GB model. Subsequent launches use the cached model.

### Server not starting
Re-run the installer: `bash install.sh`. To verify dependencies manually:
```bash
~/.voicescribe/venv/bin/python3 -c "import mlx_audio; print('OK')"
```

### Intel Mac
VoiceScribe requires Apple Silicon. MLX does not support Intel processors.

## Privacy

VoiceScribe processes all audio **locally on your device**:
- No audio is sent to external servers
- No transcriptions are stored or transmitted
- No analytics or telemetry

The only network requests are to download the AI model from Hugging Face on first launch.

## Tech Stack

- **Swift / SwiftUI** — Native macOS app
- **MLX Audio** — Apple Silicon-optimized ML inference
- **Parakeet TDT 0.6B** — NVIDIA's speech recognition model
- **Python** — Transcription server backend

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [MLX Audio](https://github.com/Blaizzy/mlx-audio) by Prince Canuma — The ML framework powering transcription
- [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b) by NVIDIA — The speech recognition model
- [Apple MLX](https://github.com/ml-explore/mlx) — Machine learning on Apple Silicon

---

<p align="center">
  Made with ❤️ for the Mac
</p>
