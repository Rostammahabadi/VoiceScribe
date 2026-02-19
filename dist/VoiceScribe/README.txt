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

2. In Terminal, type:  cd
   (that's "cd" followed by a space — do NOT press Enter yet)

3. Drag this VoiceScribe folder into the Terminal window.
   The folder path will appear. Now press Enter.

4. Type:  bash install.sh
   and press Enter.

   The installer will automatically:
   • Check that your Mac is compatible
   • Find or install Python 3
   • Set up a virtual environment with all dependencies
   • Copy VoiceScribe.app to /Applications
   • Verify everything works

5. Open VoiceScribe from Applications (or Spotlight)

6. Grant permissions when prompted:
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

FAQ / TROUBLESHOOTING
────────────────────────────────────────────────────────────────────

Q: Where do I grant Accessibility permission?
A: System Settings → Privacy & Security → Accessibility
   Find VoiceScribe in the list and toggle it ON.
   If VoiceScribe is not listed, click the "+" button, navigate
   to /Applications, and add VoiceScribe.app.
   You may need to quit and reopen VoiceScribe after granting.

Q: Where do I grant Microphone permission?
A: System Settings → Privacy & Security → Microphone
   Find VoiceScribe in the list and toggle it ON.
   If it's not listed, the app will ask on your first recording.

Q: The Globe (Fn) key doesn't start recording.
A: Three things to check:
   1. Make sure Accessibility permission is granted (see above)
   2. Make sure the server status shows "Ready" in Settings → General
   3. If Globe opens the emoji picker instead, go to:
      System Settings → Keyboard → "Press Globe key to" → "Do Nothing"
   If all else fails, try switching to Right Option in
   Settings → Shortcuts.

Q: "Model loading..." takes a very long time.
A: The first launch downloads the Parakeet AI model (~1.2GB).
   This can take several minutes on a slow connection. Subsequent
   launches will be much faster since the model is cached locally.

Q: Server status shows "Error" or "Starting" and never becomes Ready.
A: This usually means Python or the dependencies aren't set up:
   1. Re-run the installer: bash install.sh
   2. Check that the installer finished with "Installation Complete"
   3. Quit and reopen VoiceScribe
   If the problem persists, open Terminal and run:
     ~/.voicescribe/venv/bin/python3 -c "import mlx_audio; print('OK')"
   If this prints "OK", the dependencies are installed correctly.

Q: Transcription quality is poor or text is garbled.
A: Check your microphone selection in Settings → Audio. Make sure
   you're using a good microphone and speaking clearly. Background
   noise can reduce accuracy.

Q: The app doesn't appear in my menu bar.
A: VoiceScribe runs as a menu bar app (no dock icon). Look for the
   waveform icon (circular sound wave) in the right side of your
   menu bar near the clock.

Q: How do I uninstall VoiceScribe?
A: 1. Delete /Applications/VoiceScribe.app
   2. Delete ~/.voicescribe/ (open Terminal and run: rm -rf ~/.voicescribe)
   3. Remove VoiceScribe from Accessibility and Microphone in
      System Settings → Privacy & Security

TECHNICAL DETAILS
────────────────────────────────────────────────────────────────────
• Uses MLX Audio library optimized for Apple Silicon
• Runs NVIDIA Parakeet TDT 0.6B model locally
• All processing happens on-device (no cloud)
• Transcription server runs on localhost:8765
• Python virtual environment: ~/.voicescribe/venv/
• Server script: ~/.voicescribe/transcription_server.py
