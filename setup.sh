#!/bin/bash
# VoiceScribe — Full Setup Script
# Installs dependencies, builds the app, and installs to /Applications.

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "=============================="
echo "  VoiceScribe Setup"
echo "=============================="
echo ""

# ── 1. Check prerequisites ──────────────────────────────────────────────────

# Apple Silicon check
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo "ERROR: VoiceScribe requires Apple Silicon (M1/M2/M3/M4)."
    echo "       Detected architecture: $ARCH"
    exit 1
fi

# Python check
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is required but not found."
    echo "       Install it with: brew install python3"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "[1/4] Python $PYTHON_VERSION found"

# Xcode CLI tools check
if ! command -v xcodebuild &> /dev/null; then
    echo "ERROR: Xcode Command Line Tools are required."
    echo "       Install with: xcode-select --install"
    exit 1
fi
echo "       Xcode CLI tools found"

# ── 2. Python virtual environment + dependencies ────────────────────────────

echo ""
if [ -d "venv" ]; then
    # Verify existing venv works
    if ! "venv/bin/python3" --version &> /dev/null; then
        echo "[2/4] Existing venv is broken (Python version changed). Recreating..."
        python3 -m venv venv --clear
    else
        echo "[2/4] Python venv already exists"
    fi
else
    echo "[2/4] Creating Python virtual environment..."
    python3 -m venv venv
fi

echo "       Installing Python dependencies (mlx-audio)..."
venv/bin/pip install --upgrade pip --quiet 2>/dev/null
venv/bin/pip install mlx-audio --quiet
echo "       Dependencies installed"

# ── 3. Build the app ────────────────────────────────────────────────────────

echo ""
echo "[3/4] Building VoiceScribe.app..."

# Ensure Xcode tools are ready (fixes simulator plugin errors)
xcodebuild -runFirstLaunch 2>/dev/null || true

xcodebuild \
    -project VoiceScribe.xcodeproj \
    -scheme VoiceScribe \
    -configuration Release \
    build \
    SYMROOT=build \
    2>&1 | tail -1

if [ ! -d "build/Release/VoiceScribe.app" ]; then
    echo "ERROR: Build failed. Run xcodebuild manually to see errors."
    exit 1
fi
echo "       Build succeeded"

# ── 4. Install to /Applications ─────────────────────────────────────────────

echo ""
echo "[4/4] Installing to /Applications..."
rsync -a --delete build/Release/VoiceScribe.app/ /Applications/VoiceScribe.app/
echo "       Installed to /Applications/VoiceScribe.app"

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
echo "=============================="
echo "  Setup complete!"
echo "=============================="
echo ""
echo "To launch:  open /Applications/VoiceScribe.app"
echo "   or run:  ./run.sh"
echo ""
echo "On first launch you will need to:"
echo "  1. Grant Accessibility permission when prompted"
echo "     (System Settings > Privacy & Security > Accessibility > add VoiceScribe)"
echo "  2. Grant Microphone permission when prompted"
echo "  3. Wait ~30s for the AI model to download on first run (~1.2GB)"
echo ""
echo "Default shortcut: hold Right Option key to record, release to transcribe."
