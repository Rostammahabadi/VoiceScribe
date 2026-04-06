#!/usr/bin/env python3
"""
VoiceScribe Transcription Server
Uses mlx-audio with Parakeet model for speech-to-text transcription.
Communicates with the Swift app via a local HTTP server.
"""

import os
import sys
import json
import tempfile
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import signal
import urllib.request

# Global model instance
model = None
model_lock = threading.Lock()
model_loaded = False

def load_parakeet_model():
    """Load the Parakeet model on startup and warm up Metal shaders."""
    global model, model_loaded
    print("Loading Parakeet model...", flush=True)
    try:
        from mlx_audio.stt.utils import load_model
        loaded = load_model("mlx-community/parakeet-tdt-0.6b-v2")
        with model_lock:
            model = loaded
            model_loaded = True
        print("Parakeet model loaded successfully!", flush=True)

        # Warm up: run a tiny silent audio through the model to trigger
        # Metal shader JIT compilation now instead of on the first real request.
        print("Warming up inference (compiling Metal shaders)...", flush=True)
        warmup_path = None
        try:
            import wave, struct
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
                warmup_path = f.name
                with wave.open(f, 'w') as w:
                    w.setnchannels(1)
                    w.setsampwidth(2)
                    w.setframerate(16000)
                    w.writeframes(struct.pack('<' + 'h' * 8000, *([0] * 8000)))
            with model_lock:
                model.generate(warmup_path)
            print("Warm-up complete — first transcription will be fast!", flush=True)
        except Exception as e:
            print(f"Warm-up failed (non-fatal): {e}", flush=True)
        finally:
            if warmup_path:
                try:
                    os.unlink(warmup_path)
                except:
                    pass

        return True
    except Exception as e:
        print(f"Error loading model: {e}", flush=True)
        return False

def cleanup_text(text: str) -> str:
    """Clean up transcribed text using nemotron-mini via local Ollama.

    Removes speech artifacts (um, uh, like, you know, etc.) and fixes
    minor grammar issues while preserving the original meaning.
    Returns the original text if Ollama is unavailable or the text is already clean.
    """
    if not text or not text.strip():
        return text

    prompt = (
        "Clean up the following transcribed speech. Remove filler words like "
        "'um', 'uh', 'like', 'you know', 'so', 'actually', 'basically', "
        "'I mean', 'right', 'well' when they are used as speech fillers. "
        "Fix minor grammar issues and ensure the text reads naturally. "
        "Do NOT change the meaning, tone, or content. If the text is already "
        "clear and well-formed, return it exactly as-is. "
        "Return ONLY the cleaned text with no explanations, no quotes, no prefixes.\n\n"
        f"Text: {text}"
    )

    payload = json.dumps({
        "model": "nemotron-mini",
        "prompt": prompt,
        "stream": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        "http://localhost:11434/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            cleaned = result.get("response", "").strip()
            if cleaned:
                return cleaned
    except Exception as e:
        print(f"Ollama cleanup failed, using original text: {e}", flush=True)

    return text


def transcribe_audio(audio_path: str) -> dict:
    """Transcribe audio file using the loaded Parakeet model."""
    try:
        with model_lock:
            if model is None:
                return {"error": "Model not loaded", "text": ""}
            # Parakeet model expects path as positional argument
            result = model.generate(audio_path)
            return {"text": result.text, "error": None}
    except Exception as e:
        return {"error": str(e), "text": ""}

class TranscriptionHandler(BaseHTTPRequestHandler):
    """HTTP request handler for transcription requests."""

    def log_message(self, format, *args):
        """Suppress default logging."""
        pass

    def send_json_response(self, data: dict, status: int = 200):
        """Send a JSON response."""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)

        if parsed.path == '/health':
            with model_lock:
                loaded = model_loaded
            self.send_json_response({
                "status": "ok",
                "model_loaded": loaded
            })
        elif parsed.path == '/status':
            with model_lock:
                loaded = model_loaded
            self.send_json_response({
                "model_loaded": loaded,
                "model_name": "parakeet-tdt-0.6b-v2"
            })
        else:
            self.send_json_response({"error": "Not found"}, 404)

    def do_POST(self):
        """Handle POST requests."""
        parsed = urlparse(self.path)

        if parsed.path == '/transcribe':
            query_params = parse_qs(parsed.query)
            do_cleanup = query_params.get('cleanup', ['false'])[0].lower() == 'true'

            try:
                content_length = int(self.headers['Content-Length'])
            except (TypeError, ValueError):
                self.send_json_response({"error": "Missing or invalid Content-Length header"}, 400)
                return
            post_data = self.rfile.read(content_length)

            # Save audio data to temporary file
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
                f.write(post_data)
                temp_path = f.name

            try:
                result = transcribe_audio(temp_path)
                if do_cleanup and result.get("text") and not result.get("error"):
                    result["original_text"] = result["text"]
                    result["text"] = cleanup_text(result["text"])
                self.send_json_response(result)
            finally:
                # Clean up temp file
                try:
                    os.unlink(temp_path)
                except:
                    pass

        elif parsed.path == '/transcribe-file':
            try:
                content_length = int(self.headers['Content-Length'])
            except (TypeError, ValueError):
                self.send_json_response({"error": "Missing or invalid Content-Length header"}, 400)
                return
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode('utf-8'))
            except (json.JSONDecodeError, UnicodeDecodeError):
                self.send_json_response({"error": "Invalid JSON in request body"}, 400)
                return

            if 'path' not in data:
                self.send_json_response({"error": "No path provided"}, 400)
                return

            file_path = data['path']

            # Validate the path
            if not os.path.isfile(file_path):
                self.send_json_response({"error": "File not found"}, 404)
                return

            # Only allow audio file extensions
            allowed_extensions = {'.wav', '.mp3', '.m4a', '.flac', '.ogg', '.aac'}
            _, ext = os.path.splitext(file_path)
            if ext.lower() not in allowed_extensions:
                self.send_json_response({"error": "Unsupported file type"}, 400)
                return

            result = transcribe_audio(file_path)
            self.send_json_response(result)

        else:
            self.send_json_response({"error": "Not found"}, 404)

    def do_OPTIONS(self):
        """Handle CORS preflight requests."""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

def run_server(port: int = 8765):
    """Run the transcription server."""
    server = ReusableHTTPServer(('127.0.0.1', port), TranscriptionHandler)
    print(f"Transcription server running on http://127.0.0.1:{port}", flush=True)

    def signal_handler(sig, frame):
        print("\nShutting down server...", flush=True)
        server.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    server.serve_forever()

if __name__ == '__main__':
    port = int(os.environ.get('VOICESCRIBE_PORT', 8765))

    # Start model loading in background thread
    model_thread = threading.Thread(target=load_parakeet_model, daemon=True)
    model_thread.start()

    # Start server immediately (health endpoint will report model_loaded=False until ready)
    run_server(port)
