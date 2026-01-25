#!/bin/bash
# VoiceScribe Setup Script

set -e

echo "Setting up VoiceScribe..."

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is required but not found. Please install Python 3."
    exit 1
fi

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate

# Install dependencies
echo "Installing Python dependencies..."
pip install --upgrade pip
pip install mlx-audio

echo ""
echo "Setup complete!"
echo ""
echo "To run VoiceScribe:"
echo "  1. Start the transcription server: ./run_server.sh"
echo "  2. Build and run the Swift app in Xcode"
echo ""
echo "Or use: ./run.sh to start everything"
