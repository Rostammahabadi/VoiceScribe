#!/bin/bash
# Start the VoiceScribe transcription server

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check if virtual environment exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

echo "Starting VoiceScribe transcription server..."
echo "This will load the Parakeet model (may take a moment on first run)..."
echo ""

python3 transcription_server.py
