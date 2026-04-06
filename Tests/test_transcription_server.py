import unittest
import json
import os
import tempfile
import threading
import time
from http.server import HTTPServer
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

# Test the server handler
class TestTranscriptionServer(unittest.TestCase):
    """Tests for transcription_server.py fixes."""

    @classmethod
    def setUpClass(cls):
        """Start test server."""
        import sys
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from transcription_server import TranscriptionHandler

        cls.server = HTTPServer(('127.0.0.1', 0), TranscriptionHandler)
        cls.port = cls.server.server_address[1]
        cls.base_url = f'http://127.0.0.1:{cls.port}'
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_health_endpoint_before_model_load(self):
        """H1: Health endpoint should be reachable even before model loads."""
        resp = urlopen(f'{self.base_url}/health')
        data = json.loads(resp.read())
        self.assertEqual(data['status'], 'ok')
        # model_loaded may be False if model hasn't loaded yet
        self.assertIn('model_loaded', data)

    def test_missing_content_length_transcribe(self):
        """M3: Missing Content-Length on /transcribe should return 411, not crash."""
        import http.client
        conn = http.client.HTTPConnection('127.0.0.1', self.port)
        conn.putrequest('POST', '/transcribe')
        conn.putheader('Content-Type', 'audio/wav')
        conn.endheaders()
        resp = conn.getresponse()
        self.assertEqual(resp.status, 411)
        conn.close()

    def test_missing_content_length_transcribe_file(self):
        """M3: Missing Content-Length on /transcribe-file should return 411, not crash."""
        import http.client
        conn = http.client.HTTPConnection('127.0.0.1', self.port)
        conn.putrequest('POST', '/transcribe-file')
        conn.putheader('Content-Type', 'application/json')
        conn.endheaders()
        resp = conn.getresponse()
        self.assertEqual(resp.status, 411)
        conn.close()

    def test_transcribe_file_missing_path(self):
        """M2: /transcribe-file should reject missing path."""
        data = json.dumps({}).encode()
        req = Request(f'{self.base_url}/transcribe-file', data=data,
                      headers={'Content-Type': 'application/json'})
        try:
            urlopen(req)
            self.fail("Expected error")
        except HTTPError as e:
            self.assertEqual(e.code, 400)

    def test_transcribe_file_nonexistent_path(self):
        """M2: /transcribe-file should reject non-existent file."""
        data = json.dumps({"path": "/nonexistent/file.wav"}).encode()
        req = Request(f'{self.base_url}/transcribe-file', data=data,
                      headers={'Content-Type': 'application/json'})
        try:
            urlopen(req)
            self.fail("Expected error")
        except HTTPError as e:
            self.assertEqual(e.code, 404)

    def test_transcribe_file_bad_extension(self):
        """M2: /transcribe-file should reject non-audio extensions."""
        with tempfile.NamedTemporaryFile(suffix='.txt', delete=False) as f:
            f.write(b'not audio')
            path = f.name
        try:
            data = json.dumps({"path": path}).encode()
            req = Request(f'{self.base_url}/transcribe-file', data=data,
                          headers={'Content-Type': 'application/json'})
            try:
                urlopen(req)
                self.fail("Expected error")
            except HTTPError as e:
                self.assertEqual(e.code, 400)
        finally:
            os.unlink(path)

    def test_404_for_unknown_endpoints(self):
        """Unknown endpoints should return 404."""
        try:
            urlopen(f'{self.base_url}/unknown')
            self.fail("Expected 404")
        except HTTPError as e:
            self.assertEqual(e.code, 404)


if __name__ == '__main__':
    unittest.main()
