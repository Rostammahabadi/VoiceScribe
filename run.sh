#!/bin/bash
# Run VoiceScribe (both server and app)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check if setup has been run
if [ ! -d "venv" ]; then
    echo "Virtual environment not found. Running setup first..."
    ./setup.sh
fi

# Start the server in background
echo "Starting transcription server..."
./run_server.sh &
SERVER_PID=$!

# Wait for server to be ready
echo "Waiting for server to be ready..."
sleep 3

# Check if we have a built app
APP_PATH="./build/Build/Products/Debug/VoiceScribe.app"
if [ -d "$APP_PATH" ]; then
    echo "Launching VoiceScribe app..."
    open "$APP_PATH"
else
    echo ""
    echo "VoiceScribe app not built yet."
    echo "Build the app in Xcode or run:"
    echo "  xcodebuild -project VoiceScribe.xcodeproj -scheme VoiceScribe -configuration Debug build"
    echo ""
    echo "Server is running. Press Ctrl+C to stop."
    wait $SERVER_PID
fi

# Cleanup on exit
trap "kill $SERVER_PID 2>/dev/null" EXIT
