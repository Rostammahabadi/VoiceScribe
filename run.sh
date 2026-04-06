#!/bin/bash
# Launch VoiceScribe — runs setup if needed, then opens the app.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Run setup if app isn't installed yet
if [ ! -d "/Applications/VoiceScribe.app" ]; then
    echo "VoiceScribe not installed. Running setup..."
    echo ""
    ./setup.sh
fi

# Kill any existing instances to avoid port conflicts
pkill -f "VoiceScribe.app/Contents/MacOS/VoiceScribe" 2>/dev/null
pkill -f "transcription_server.py" 2>/dev/null
sleep 1

echo "Launching VoiceScribe..."
open /Applications/VoiceScribe.app
