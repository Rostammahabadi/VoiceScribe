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

# Global model instance
model = None
model_lock = threading.Lock()
model_loaded = False

def load_parakeet_model():
    """Load the Parakeet model on startup."""
    global model, model_loaded
    print("Loading Parakeet model...", flush=True)
    try:
        from mlx_audio.stt.utils import load_model
        model = load_model("mlx-community/parakeet-tdt-0.6b-v2")
        model_loaded = True
        print("Parakeet model loaded successfully!", flush=True)
        return True
    except Exception as e:
        print(f"Error loading model: {e}", flush=True)
        return False

def transcribe_audio(audio_path: str) -> dict:
    """Transcribe audio file using the loaded Parakeet model."""
    global model
    if model is None:
        return {"error": "Model not loaded", "text": ""}

    try:
        with model_lock:
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
            self.send_json_response({
                "status": "ok",
                "model_loaded": model_loaded
            })
        elif parsed.path == '/status':
            self.send_json_response({
                "model_loaded": model_loaded,
                "model_name": "parakeet-tdt-0.6b-v2"
            })
        else:
            self.send_json_response({"error": "Not found"}, 404)

    def do_POST(self):
        """Handle POST requests."""
        parsed = urlparse(self.path)

        if parsed.path == '/transcribe':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)

            # Save audio data to temporary file
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
                f.write(post_data)
                temp_path = f.name

            try:
                result = transcribe_audio(temp_path)
                self.send_json_response(result)
            finally:
                # Clean up temp file
                try:
                    os.unlink(temp_path)
                except:
                    pass

        elif parsed.path == '/transcribe-file':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data.decode('utf-8'))

            if 'path' not in data:
                self.send_json_response({"error": "No path provided"}, 400)
                return

            result = transcribe_audio(data['path'])
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

def run_server(port: int = 8765):
    """Run the transcription server."""
    server = HTTPServer(('127.0.0.1', port), TranscriptionHandler)
    print(f"Transcription server running on http://127.0.0.1:{port}", flush=True)

    def signal_handler(sig, frame):
        print("\nShutting down server...", flush=True)
        server.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    server.serve_forever()

if __name__ == '__main__':
    # Load model first
    if load_parakeet_model():
        # Then start server
        port = int(os.environ.get('VOICESCRIBE_PORT', 8765))
        run_server(port)
    else:
        print("Failed to load model. Exiting.", flush=True)
        sys.exit(1)
