#!/bin/bash
# VoiceScribe Installer
# Installs VoiceScribe and its dependencies for macOS on Apple Silicon.

set -euo pipefail

# --- Path anchoring ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOICESCRIBE_DIR="$HOME/.voicescribe"
VENV_DIR="$VOICESCRIBE_DIR/venv"

# --- Terminal-aware colors ---
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

# --- Helpers ---
step() {
    echo ""
    echo -e "${BLUE}${BOLD}[$1/8]${RESET} ${BOLD}$2${RESET}"
}

ok() {
    echo -e "  ${GREEN}✔${RESET} $1"
}

fail() {
    echo -e "  ${RED}✖ $1${RESET}" >&2
    exit 1
}

warn() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
}

# --- Friendly error trap ---
trap 'echo ""; echo -e "${RED}${BOLD}Installation failed.${RESET} See the error above for details."; echo "If you need help, open an issue with the error message."' ERR

echo ""
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "${BOLD}        VoiceScribe Installer${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"

# ── Step 1: Check Apple Silicon ──────────────────────────────────────────
step 1 "Checking for Apple Silicon..."

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
    fail "VoiceScribe requires Apple Silicon (M1/M2/M3/M4).
         Your Mac has an Intel ($ARCH) processor.
         MLX, the AI framework VoiceScribe uses, only runs on Apple Silicon.
         Unfortunately VoiceScribe cannot work on this Mac."
fi
ok "Apple Silicon detected ($ARCH)"

# ── Step 2: Check macOS version ──────────────────────────────────────────
step 2 "Checking macOS version..."

MACOS_VERSION="$(sw_vers -productVersion)"
MAJOR_VERSION="$(echo "$MACOS_VERSION" | cut -d. -f1)"
if [[ "$MAJOR_VERSION" -lt 13 ]]; then
    fail "macOS 13.0 (Ventura) or later is required.
         You are running macOS $MACOS_VERSION.
         Please update your Mac in System Settings → General → Software Update."
fi
ok "macOS $MACOS_VERSION"

# ── Step 3: Find Python 3 ───────────────────────────────────────────────
step 3 "Finding Python 3..."

PYTHON=""

# Search order: Homebrew paths first, then system
PYTHON_SEARCH_PATHS=(
    /opt/homebrew/bin/python3
    /usr/local/bin/python3
    /opt/homebrew/bin/python3.12
    /opt/homebrew/bin/python3.11
    /opt/homebrew/bin/python3.10
    /opt/homebrew/bin/python3.9
)

for p in "${PYTHON_SEARCH_PATHS[@]}"; do
    if [[ -x "$p" ]]; then
        # Verify it's a real Python, not the Xcode CLT shim
        if "$p" --version &>/dev/null; then
            PYTHON="$p"
            break
        fi
    fi
done

# Fallback: try python3 on PATH (but verify it's not the CLT shim)
if [[ -z "$PYTHON" ]] && command -v python3 &>/dev/null; then
    if python3 --version &>/dev/null; then
        PYTHON="$(command -v python3)"
    fi
fi

# If still not found, try to auto-install via Homebrew
if [[ -z "$PYTHON" ]]; then
    if command -v brew &>/dev/null; then
        warn "Python 3 not found. Installing via Homebrew..."
        brew install python@3
        PYTHON="/opt/homebrew/bin/python3"
        if [[ ! -x "$PYTHON" ]]; then
            PYTHON="/usr/local/bin/python3"
        fi
        if [[ ! -x "$PYTHON" ]]; then
            fail "Homebrew installed Python but it can't be found. Try running:
                 brew install python@3
                 Then re-run this installer."
        fi
    else
        fail "Python 3 is required but not found.

  Install Python using one of these methods:

  Option A — Install Homebrew first, then Python:
    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
    brew install python@3

  Option B — Download Python directly:
    https://www.python.org/downloads/

  Then re-run this installer."
    fi
fi

# Verify Python version >= 3.9
PY_VERSION_STR="$("$PYTHON" --version 2>&1)"
PY_MINOR="$("$PYTHON" -c 'import sys; print(sys.version_info.minor)')"
PY_MAJOR="$("$PYTHON" -c 'import sys; print(sys.version_info.major)')"

if [[ "$PY_MAJOR" -ne 3 ]] || [[ "$PY_MINOR" -lt 9 ]]; then
    fail "Python 3.9 or later is required. Found: $PY_VERSION_STR
         Please install a newer Python version."
fi

ok "Found $PY_VERSION_STR at $PYTHON"

# ── Step 4: Create virtual environment ───────────────────────────────────
step 4 "Creating virtual environment at ~/.voicescribe/..."

mkdir -p "$VOICESCRIBE_DIR"

if [[ -d "$VENV_DIR" ]]; then
    warn "Removing existing venv..."
    rm -rf "$VENV_DIR"
fi

"$PYTHON" -m venv "$VENV_DIR"
ok "Virtual environment created"

# ── Step 5: Install mlx-audio ────────────────────────────────────────────
step 5 "Installing mlx-audio (this may take a few minutes)..."

"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null 2>&1
"$VENV_DIR/bin/pip" install mlx-audio

ok "mlx-audio installed"

# ── Step 6: Copy transcription server script ─────────────────────────────
step 6 "Installing transcription server..."

DIST_SCRIPT="$SCRIPT_DIR/transcription_server.py"
DEST_SCRIPT="$VOICESCRIBE_DIR/transcription_server.py"

if [[ -f "$DIST_SCRIPT" ]]; then
    cp "$DIST_SCRIPT" "$DEST_SCRIPT"
    ok "transcription_server.py → ~/.voicescribe/"
else
    fail "transcription_server.py not found in installer directory.
         Expected at: $DIST_SCRIPT
         Your download may be incomplete — please re-download VoiceScribe."
fi

# ── Step 7: Copy app to /Applications ────────────────────────────────────
step 7 "Installing VoiceScribe.app..."

DIST_APP="$SCRIPT_DIR/VoiceScribe.app"
DEST_APP="/Applications/VoiceScribe.app"

if [[ -d "$DIST_APP" ]]; then
    if [[ -d "$DEST_APP" ]]; then
        warn "Replacing existing VoiceScribe.app in /Applications..."
        rm -rf "$DEST_APP"
    fi
    cp -R "$DIST_APP" "$DEST_APP"
    # Remove quarantine attribute so macOS doesn't block the app
    xattr -rd com.apple.quarantine "$DEST_APP" 2>/dev/null || true
    ok "VoiceScribe.app → /Applications/"
else
    warn "VoiceScribe.app not found in installer directory — skipping."
    warn "You can manually move VoiceScribe.app to /Applications later."
fi

# ── Step 8: Verify installation ──────────────────────────────────────────
step 8 "Verifying installation..."

VERIFY_OK=true

if "$VENV_DIR/bin/python3" -c "import mlx_audio" 2>/dev/null; then
    ok "mlx_audio imports successfully"
else
    warn "mlx_audio import check failed — the app may not work correctly"
    VERIFY_OK=false
fi

if [[ -f "$DEST_SCRIPT" ]]; then
    ok "transcription_server.py is in place"
else
    warn "transcription_server.py not found at $DEST_SCRIPT"
    VERIFY_OK=false
fi

echo ""
if $VERIFY_OK; then
    echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  Installation Complete!${RESET}"
    echo -e "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
else
    echo -e "${YELLOW}${BOLD}════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}${BOLD}  Installation finished with warnings${RESET}"
    echo -e "${YELLOW}${BOLD}════════════════════════════════════════${RESET}"
fi

echo ""
echo "Next steps:"
echo "  1. Open VoiceScribe from Applications (or Spotlight)"
echo "  2. Grant Accessibility permission when prompted"
echo "     (System Settings → Privacy & Security → Accessibility)"
echo "  3. Grant Microphone permission when prompted"
echo ""
echo "Usage:"
echo "  • Hold the Globe (Fn) key and speak"
echo "  • Release to transcribe and paste"
echo ""
echo "The first launch will download the Parakeet AI model (~1.2GB)."
echo "Subsequent launches will be much faster."
echo ""
