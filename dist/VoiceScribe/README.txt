╔══════════════════════════════════════════════════════════════════╗
║                         VOICESCRIBE                               ║
║         Speech-to-Text for macOS with Local AI                   ║
╚══════════════════════════════════════════════════════════════════╝

VoiceScribe is a menu bar app that transcribes your speech using
NVIDIA's Parakeet AI model running locally on your Mac.

REQUIREMENTS
────────────────────────────────────────────────────────────────────
• macOS 13.0 or later
• Apple Silicon Mac (M1, M2, M3, or later)
• Python 3.9 or later
• ~2GB disk space (for the AI model)

INSTALLATION
────────────────────────────────────────────────────────────────────
1. Open Terminal (Applications → Utilities → Terminal)

2. Type the following into Terminal (do NOT press Enter yet):
      bash
   (that's the word "bash" followed by a space)

3. Drag the install.sh file from this folder into the Terminal
   window. The full path will appear after "bash ". Now press Enter.

   The installer will automatically:
   • Check that your Mac is compatible
   • Find or install Python 3
   • Set up a virtual environment with all dependencies
   • Copy VoiceScribe.app to /Applications
   • Verify everything works

4. Open VoiceScribe from Applications (or Spotlight)

5. Grant permissions when prompted:
   • Accessibility (required for keyboard shortcuts)
   • Microphone (required for recording)

USAGE
────────────────────────────────────────────────────────────────────
1. Click the waveform icon in your menu bar

2. Position your cursor in any text field

3. Hold the GLOBE (Fn) key and speak

4. Release the key - your speech will be transcribed and pasted

SETTINGS
────────────────────────────────────────────────────────────────────
Click the menu bar icon → Settings to configure:
• Push-to-talk key (Globe, Fn, Right Option, Right Command)
• Input microphone
• Auto-paste behavior

TROUBLESHOOTING
────────────────────────────────────────────────────────────────────
"Model loading..." takes too long
  → First launch downloads ~1.2GB model. Be patient.

Keyboard shortcut not working
  → Check Accessibility permissions in System Settings

No transcription appears
  → Check Microphone permissions in System Settings

App not responding
  → Quit and reopen. Check that Python 3 is installed.

TECHNICAL DETAILS
────────────────────────────────────────────────────────────────────
• Uses MLX Audio library optimized for Apple Silicon
• Runs NVIDIA Parakeet TDT 0.6B model locally
• All processing happens on-device (no cloud)
• Transcription server runs on localhost:8765

────────────────────────────────────────────────────────────────────
For support, contact: [your email]
