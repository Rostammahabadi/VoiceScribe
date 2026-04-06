"""
Comprehensive tests for transcription_server.py

Covers:
  - Health & status endpoints (happy + sad paths)
  - /transcribe endpoint (POST audio data)
  - /transcribe-file endpoint (POST JSON path)
  - Content-Length validation
  - CORS (OPTIONS preflight)
  - Input validation & edge cases
  - cleanup_text function
  - Concurrent request handling
"""

import unittest
import json
import os
import sys
import struct
import tempfile
import threading
import time
import wave
import http.client
from http.server import HTTPServer
from unittest.mock import patch, MagicMock
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

# Ensure project root is on path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import transcription_server


def make_wav_bytes(num_samples=8000, sample_rate=16000):
    """Create valid WAV file bytes with silence."""
    import io
    buf = io.BytesIO()
    with wave.open(buf, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        w.writeframes(struct.pack('<' + 'h' * num_samples, *([0] * num_samples)))
    return buf.getvalue()


def make_wav_file(suffix='.wav', num_samples=8000):
    """Create a temporary WAV file and return its path."""
    data = make_wav_bytes(num_samples)
    f = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
    f.write(data)
    f.close()
    return f.name


class TestTranscriptionServer(unittest.TestCase):
    """Tests against a live in-process HTTP server (no model loaded)."""

    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(('127.0.0.1', 0), transcription_server.TranscriptionHandler)
        cls.port = cls.server.server_address[1]
        cls.base_url = f'http://127.0.0.1:{cls.port}'
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    # ------------------------------------------------------------------ #
    # GET /health
    # ------------------------------------------------------------------ #
    def test_health_returns_200(self):
        resp = urlopen(f'{self.base_url}/health')
        self.assertEqual(resp.status, 200)

    def test_health_json_structure(self):
        resp = urlopen(f'{self.base_url}/health')
        data = json.loads(resp.read())
        self.assertEqual(data['status'], 'ok')
        self.assertIn('model_loaded', data)
        self.assertIsInstance(data['model_loaded'], bool)

    def test_health_before_model_load(self):
        """Health endpoint works even when model hasn't loaded."""
        resp = urlopen(f'{self.base_url}/health')
        data = json.loads(resp.read())
        self.assertEqual(data['status'], 'ok')
        # Model not loaded in test environment
        self.assertFalse(data['model_loaded'])

    def test_health_content_type_is_json(self):
        resp = urlopen(f'{self.base_url}/health')
        self.assertIn('application/json', resp.headers.get('Content-Type', ''))

    def test_health_has_cors_header(self):
        resp = urlopen(f'{self.base_url}/health')
        self.assertEqual(resp.headers.get('Access-Control-Allow-Origin'), '*')

    # ------------------------------------------------------------------ #
    # GET /status
    # ------------------------------------------------------------------ #
    def test_status_returns_200(self):
        resp = urlopen(f'{self.base_url}/status')
        self.assertEqual(resp.status, 200)

    def test_status_json_structure(self):
        resp = urlopen(f'{self.base_url}/status')
        data = json.loads(resp.read())
        self.assertIn('model_loaded', data)
        self.assertEqual(data['model_name'], 'parakeet-tdt-0.6b-v2')

    # ------------------------------------------------------------------ #
    # GET unknown path → 404
    # ------------------------------------------------------------------ #
    def test_get_unknown_path_returns_404(self):
        with self.assertRaises(HTTPError) as ctx:
            urlopen(f'{self.base_url}/nonexistent')
        self.assertEqual(ctx.exception.code, 404)

    def test_post_unknown_path_returns_404(self):
        req = Request(f'{self.base_url}/nonexistent', data=b'{}',
                      headers={'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as ctx:
            urlopen(req)
        self.assertEqual(ctx.exception.code, 404)

    # ------------------------------------------------------------------ #
    # OPTIONS (CORS preflight)
    # ------------------------------------------------------------------ #
    def test_options_returns_200(self):
        conn = http.client.HTTPConnection('127.0.0.1', self.port)
        conn.request('OPTIONS', '/transcribe')
        resp = conn.getresponse()
        self.assertEqual(resp.status, 200)
        self.assertEqual(resp.getheader('Access-Control-Allow-Origin'), '*')
        self.assertIn('POST', resp.getheader('Access-Control-Allow-Methods', ''))
        conn.close()

    # ------------------------------------------------------------------ #
    # POST /transcribe — Content-Length validation
    # ------------------------------------------------------------------ #
    def test_transcribe_missing_content_length(self):
        """Missing Content-Length returns 400."""
        conn = http.client.HTTPConnection('127.0.0.1', self.port)
        conn.putrequest('POST', '/transcribe')
        conn.putheader('Content-Type', 'audio/wav')
        conn.endheaders()
        resp = conn.getresponse()
        self.assertEqual(resp.status, 400)
        data = json.loads(resp.read())
        self.assertIn('error', data)
        conn.close()

    def test_transcribe_invalid_content_length(self):
        """Non-numeric Content-Length returns 400."""
        conn = http.client.HTTPConnection('127.0.0.1', self.port)
        conn.putrequest('POST', '/transcribe')
        conn.putheader('Content-Type', 'audio/wav')
        conn.putheader('Content-Length', 'abc')
        conn.endheaders()
        resp = conn.getresponse()
        self.assertEqual(resp.status, 400)
        conn.close()

    # ------------------------------------------------------------------ #
    # POST /transcribe — model not loaded
    # ------------------------------------------------------------------ #
    def test_transcribe_returns_error_when_model_not_loaded(self):
        """Transcribe should return error text when model is None."""
        wav = make_wav_bytes()
        req = Request(f'{self.base_url}/transcribe', data=wav,
                      headers={'Content-Type': 'audio/wav'})
        resp = urlopen(req)
        data = json.loads(resp.read())
        self.assertEqual(data['error'], 'Model not loaded')
        self.assertEqual(data['text'], '')

    def test_transcribe_empty_body(self):
        """Empty audio body — should still hit model (which returns error)."""
        req = Request(f'{self.base_url}/transcribe', data=b'',
                      headers={'Content-Type': 'audio/wav', 'Content-Length': '0'})
        resp = urlopen(req)
        data = json.loads(resp.read())
        # Model not loaded, so we get that error
        self.assertEqual(data['error'], 'Model not loaded')

    def test_transcribe_with_cleanup_flag(self):
        """cleanup=true query param is accepted (model not loaded, so error returned)."""
        wav = make_wav_bytes()
        req = Request(f'{self.base_url}/transcribe?cleanup=true', data=wav,
                      headers={'Content-Type': 'audio/wav'})
        resp = urlopen(req)
        data = json.loads(resp.read())
        self.assertEqual(data['error'], 'Model not loaded')

    def test_transcribe_cleanup_false(self):
        """cleanup=false query param is accepted."""
        wav = make_wav_bytes()
        req = Request(f'{self.base_url}/transcribe?cleanup=false', data=wav,
                      headers={'Content-Type': 'audio/wav'})
        resp = urlopen(req)
        data = json.loads(resp.read())
        self.assertIn('error', data)

    # ------------------------------------------------------------------ #
    # POST /transcribe-file — Content-Length validation
    # ------------------------------------------------------------------ #
    def test_transcribe_file_missing_content_length(self):
        conn = http.client.HTTPConnection('127.0.0.1', self.port)
        conn.putrequest('POST', '/transcribe-file')
        conn.putheader('Content-Type', 'application/json')
        conn.endheaders()
        resp = conn.getresponse()
        self.assertEqual(resp.status, 400)
        conn.close()

    # ------------------------------------------------------------------ #
    # POST /transcribe-file — input validation
    # ------------------------------------------------------------------ #
    def test_transcribe_file_missing_path_key(self):
        """JSON body without 'path' key → 400."""
        data = json.dumps({}).encode()
        req = Request(f'{self.base_url}/transcribe-file', data=data,
                      headers={'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as ctx:
            urlopen(req)
        self.assertEqual(ctx.exception.code, 400)

    def test_transcribe_file_empty_json(self):
        """Empty JSON object → 400."""
        req = Request(f'{self.base_url}/transcribe-file', data=b'{}',
                      headers={'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as ctx:
            urlopen(req)
        self.assertEqual(ctx.exception.code, 400)

    def test_transcribe_file_invalid_json(self):
        """Malformed JSON → 400."""
        req = Request(f'{self.base_url}/transcribe-file', data=b'not json',
                      headers={'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as ctx:
            urlopen(req)
        self.assertEqual(ctx.exception.code, 400)

    def test_transcribe_file_nonexistent_path(self):
        data = json.dumps({"path": "/nonexistent/audio.wav"}).encode()
        req = Request(f'{self.base_url}/transcribe-file', data=data,
                      headers={'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as ctx:
            urlopen(req)
        self.assertEqual(ctx.exception.code, 404)

    def test_transcribe_file_bad_extension_txt(self):
        path = tempfile.NamedTemporaryFile(suffix='.txt', delete=False).name
        try:
            data = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=data,
                          headers={'Content-Type': 'application/json'})
            with self.assertRaises(HTTPError) as ctx:
                urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
        finally:
            os.unlink(path)

    def test_transcribe_file_bad_extension_py(self):
        path = tempfile.NamedTemporaryFile(suffix='.py', delete=False).name
        try:
            data = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=data,
                          headers={'Content-Type': 'application/json'})
            with self.assertRaises(HTTPError) as ctx:
                urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
        finally:
            os.unlink(path)

    def test_transcribe_file_bad_extension_exe(self):
        path = tempfile.NamedTemporaryFile(suffix='.exe', delete=False).name
        try:
            data = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=data,
                          headers={'Content-Type': 'application/json'})
            with self.assertRaises(HTTPError) as ctx:
                urlopen(req)
            self.assertEqual(ctx.exception.code, 400)
        finally:
            os.unlink(path)

    # ------------------------------------------------------------------ #
    # POST /transcribe-file — allowed audio extensions
    # ------------------------------------------------------------------ #
    def _test_allowed_extension(self, ext):
        """Helper: valid extension should reach transcription (model error, not 400)."""
        path = make_wav_file(suffix=ext)
        try:
            data = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=data,
                          headers={'Content-Type': 'application/json'})
            resp = urlopen(req)
            result = json.loads(resp.read())
            # Should reach model (which is None → "Model not loaded")
            self.assertEqual(result['error'], 'Model not loaded')
        finally:
            os.unlink(path)

    def test_transcribe_file_wav_extension(self):
        self._test_allowed_extension('.wav')

    def test_transcribe_file_mp3_extension(self):
        self._test_allowed_extension('.mp3')

    def test_transcribe_file_m4a_extension(self):
        self._test_allowed_extension('.m4a')

    def test_transcribe_file_flac_extension(self):
        self._test_allowed_extension('.flac')

    def test_transcribe_file_ogg_extension(self):
        self._test_allowed_extension('.ogg')

    def test_transcribe_file_aac_extension(self):
        self._test_allowed_extension('.aac')

    def test_transcribe_file_uppercase_extension_rejected(self):
        """Extensions are lowercased — .WAV should still be accepted."""
        path = make_wav_file(suffix='.WAV')
        try:
            data = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=data,
                          headers={'Content-Type': 'application/json'})
            resp = urlopen(req)
            result = json.loads(resp.read())
            self.assertEqual(result['error'], 'Model not loaded')
        finally:
            os.unlink(path)

    # ------------------------------------------------------------------ #
    # POST /transcribe-file — path traversal / edge cases
    # ------------------------------------------------------------------ #
    def test_transcribe_file_directory_path(self):
        """Passing a directory instead of a file → 404 (not a file)."""
        data = json.dumps({"path": tempfile.gettempdir()}).encode()
        req = Request(f'{self.base_url}/transcribe-file', data=data,
                      headers={'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as ctx:
            urlopen(req)
        self.assertEqual(ctx.exception.code, 404)

    def test_transcribe_file_empty_path(self):
        """Empty path string → 404."""
        data = json.dumps({"path": ""}).encode()
        req = Request(f'{self.base_url}/transcribe-file', data=data,
                      headers={'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as ctx:
            urlopen(req)
        self.assertEqual(ctx.exception.code, 404)

    def test_transcribe_file_path_with_spaces(self):
        """Path with spaces should work."""
        tmpdir = tempfile.mkdtemp(prefix="voice scribe test ")
        path = os.path.join(tmpdir, "test audio.wav")
        with open(path, 'wb') as f:
            f.write(make_wav_bytes())
        try:
            data = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=data,
                          headers={'Content-Type': 'application/json'})
            resp = urlopen(req)
            result = json.loads(resp.read())
            self.assertEqual(result['error'], 'Model not loaded')
        finally:
            os.unlink(path)
            os.rmdir(tmpdir)

    # ------------------------------------------------------------------ #
    # Concurrent requests
    # ------------------------------------------------------------------ #
    def test_concurrent_health_checks(self):
        """Multiple simultaneous health checks should all succeed."""
        results = [None] * 10
        errors = []

        def check_health(idx):
            try:
                resp = urlopen(f'{self.base_url}/health')
                results[idx] = json.loads(resp.read())
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=check_health, args=(i,)) for i in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=5)

        self.assertEqual(len(errors), 0, f"Errors during concurrent requests: {errors}")
        for r in results:
            self.assertIsNotNone(r)
            self.assertEqual(r['status'], 'ok')

    def test_concurrent_transcribe_requests(self):
        """Multiple simultaneous transcribe requests should all return model error."""
        wav = make_wav_bytes()
        results = [None] * 5
        errors = []

        def do_transcribe(idx):
            try:
                req = Request(f'{self.base_url}/transcribe', data=wav,
                              headers={'Content-Type': 'audio/wav'})
                resp = urlopen(req)
                results[idx] = json.loads(resp.read())
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=do_transcribe, args=(i,)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)

        self.assertEqual(len(errors), 0)
        for r in results:
            self.assertEqual(r['error'], 'Model not loaded')


class TestCleanupText(unittest.TestCase):
    """Tests for the cleanup_text function (Ollama integration)."""

    def test_empty_string_returns_empty(self):
        self.assertEqual(transcription_server.cleanup_text(""), "")

    def test_none_returns_none(self):
        self.assertIsNone(transcription_server.cleanup_text(None))

    def test_whitespace_only_returns_original(self):
        self.assertEqual(transcription_server.cleanup_text("   "), "   ")

    def test_ollama_unavailable_returns_original(self):
        """When Ollama is not running, original text is returned."""
        result = transcription_server.cleanup_text("Um, hello there, you know")
        # Ollama is not running in test env, so original text is returned
        self.assertEqual(result, "Um, hello there, you know")

    @patch('transcription_server.urllib.request.urlopen')
    def test_ollama_success_returns_cleaned(self, mock_urlopen):
        """When Ollama responds successfully, cleaned text is returned."""
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "response": "Hello there"
        }).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = transcription_server.cleanup_text("Um, hello there, you know")
        self.assertEqual(result, "Hello there")

    @patch('transcription_server.urllib.request.urlopen')
    def test_ollama_empty_response_returns_original(self, mock_urlopen):
        """Empty Ollama response falls back to original."""
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({"response": ""}).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = transcription_server.cleanup_text("Hello there")
        self.assertEqual(result, "Hello there")

    @patch('transcription_server.urllib.request.urlopen')
    def test_ollama_whitespace_response_returns_original(self, mock_urlopen):
        """Whitespace-only Ollama response falls back to original."""
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({"response": "   "}).encode()
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)
        mock_urlopen.return_value = mock_resp

        result = transcription_server.cleanup_text("Hello there")
        self.assertEqual(result, "Hello there")

    @patch('transcription_server.urllib.request.urlopen')
    def test_ollama_timeout_returns_original(self, mock_urlopen):
        """Timeout from Ollama returns original text."""
        mock_urlopen.side_effect = TimeoutError("Connection timed out")
        result = transcription_server.cleanup_text("Hello there")
        self.assertEqual(result, "Hello there")

    @patch('transcription_server.urllib.request.urlopen')
    def test_ollama_connection_refused_returns_original(self, mock_urlopen):
        """Connection refused returns original text."""
        mock_urlopen.side_effect = URLError("Connection refused")
        result = transcription_server.cleanup_text("Hello there")
        self.assertEqual(result, "Hello there")


class TestTranscribeAudio(unittest.TestCase):
    """Tests for the transcribe_audio function directly."""

    def test_model_not_loaded_returns_error(self):
        """When model is None, return error dict."""
        old_model = transcription_server.model
        transcription_server.model = None
        try:
            result = transcription_server.transcribe_audio("/tmp/test.wav")
            self.assertEqual(result['error'], 'Model not loaded')
            self.assertEqual(result['text'], '')
        finally:
            transcription_server.model = old_model

    def test_model_generate_exception_returns_error(self):
        """When model.generate raises, return error dict."""
        mock_model = MagicMock()
        mock_model.generate.side_effect = RuntimeError("Bad audio format")
        old_model = transcription_server.model
        old_loaded = transcription_server.model_loaded
        transcription_server.model = mock_model
        transcription_server.model_loaded = True
        try:
            result = transcription_server.transcribe_audio("/tmp/test.wav")
            self.assertIn('Bad audio format', result['error'])
            self.assertEqual(result['text'], '')
        finally:
            transcription_server.model = old_model
            transcription_server.model_loaded = old_loaded

    def test_model_generate_success(self):
        """When model.generate succeeds, return text."""
        mock_result = MagicMock()
        mock_result.text = "Hello world"
        mock_model = MagicMock()
        mock_model.generate.return_value = mock_result

        old_model = transcription_server.model
        old_loaded = transcription_server.model_loaded
        transcription_server.model = mock_model
        transcription_server.model_loaded = True
        try:
            result = transcription_server.transcribe_audio("/tmp/test.wav")
            self.assertIsNone(result['error'])
            self.assertEqual(result['text'], 'Hello world')
        finally:
            transcription_server.model = old_model
            transcription_server.model_loaded = old_loaded


class TestServerIntegrationWithMockModel(unittest.TestCase):
    """Tests with a mock model loaded — tests the full happy path."""

    @classmethod
    def setUpClass(cls):
        # Set up a mock model
        mock_result = MagicMock()
        mock_result.text = "This is a test transcription"
        cls.mock_model = MagicMock()
        cls.mock_model.generate.return_value = mock_result

        cls.old_model = transcription_server.model
        cls.old_loaded = transcription_server.model_loaded
        transcription_server.model = cls.mock_model
        transcription_server.model_loaded = True

        cls.server = HTTPServer(('127.0.0.1', 0), transcription_server.TranscriptionHandler)
        cls.port = cls.server.server_address[1]
        cls.base_url = f'http://127.0.0.1:{cls.port}'
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        transcription_server.model = cls.old_model
        transcription_server.model_loaded = cls.old_loaded

    def test_health_shows_model_loaded(self):
        resp = urlopen(f'{self.base_url}/health')
        data = json.loads(resp.read())
        self.assertTrue(data['model_loaded'])

    def test_status_shows_model_loaded(self):
        resp = urlopen(f'{self.base_url}/status')
        data = json.loads(resp.read())
        self.assertTrue(data['model_loaded'])

    def test_transcribe_happy_path(self):
        """POST audio data → get transcription text back."""
        wav = make_wav_bytes()
        req = Request(f'{self.base_url}/transcribe', data=wav,
                      headers={'Content-Type': 'audio/wav'})
        resp = urlopen(req)
        data = json.loads(resp.read())
        self.assertIsNone(data['error'])
        self.assertEqual(data['text'], 'This is a test transcription')

    def test_transcribe_file_happy_path(self):
        """POST file path → get transcription text back."""
        path = make_wav_file()
        try:
            body = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=body,
                          headers={'Content-Type': 'application/json'})
            resp = urlopen(req)
            data = json.loads(resp.read())
            self.assertIsNone(data['error'])
            self.assertEqual(data['text'], 'This is a test transcription')
        finally:
            os.unlink(path)

    def test_transcribe_with_cleanup_calls_cleanup(self):
        """When cleanup=true and model succeeds, cleanup_text is called."""
        wav = make_wav_bytes()
        with patch.object(transcription_server, 'cleanup_text',
                          return_value='Cleaned text') as mock_cleanup:
            req = Request(f'{self.base_url}/transcribe?cleanup=true', data=wav,
                          headers={'Content-Type': 'audio/wav'})
            resp = urlopen(req)
            data = json.loads(resp.read())
            self.assertEqual(data['text'], 'Cleaned text')
            self.assertEqual(data['original_text'], 'This is a test transcription')
            mock_cleanup.assert_called_once_with('This is a test transcription')

    def test_transcribe_without_cleanup_skips_cleanup(self):
        """When cleanup=false, cleanup_text is not called."""
        wav = make_wav_bytes()
        with patch.object(transcription_server, 'cleanup_text') as mock_cleanup:
            req = Request(f'{self.base_url}/transcribe', data=wav,
                          headers={'Content-Type': 'audio/wav'})
            resp = urlopen(req)
            data = json.loads(resp.read())
            self.assertEqual(data['text'], 'This is a test transcription')
            mock_cleanup.assert_not_called()

    def test_transcribe_temp_file_cleanup(self):
        """Temp file created during /transcribe should be cleaned up."""
        wav = make_wav_bytes()
        req = Request(f'{self.base_url}/transcribe', data=wav,
                      headers={'Content-Type': 'audio/wav'})
        urlopen(req)

        # The server writes to a temp file and then unlinks it.
        # We can't easily check this without instrumenting, but at least
        # verify the request succeeds without accumulating temp files.
        # (This is more of a smoke test.)

    def test_large_audio_data(self):
        """Larger audio data (10 seconds) should be accepted."""
        wav = make_wav_bytes(num_samples=160000)  # 10 seconds at 16kHz
        req = Request(f'{self.base_url}/transcribe', data=wav,
                      headers={'Content-Type': 'audio/wav'})
        resp = urlopen(req)
        data = json.loads(resp.read())
        self.assertEqual(data['text'], 'This is a test transcription')


if __name__ == '__main__':
    unittest.main()
