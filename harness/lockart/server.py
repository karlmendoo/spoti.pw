"""Loopback-only download fixture; count coalesced requests and delay cancellation checks."""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

counts = {}
lock = Lock()
report = Path(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with lock:
            counts[self.path] = counts.get(self.path, 0) + 1
            report.write_text(json.dumps(counts))
        time.sleep(0.5)
        data = b"download fixture" * 1024
        self.send_response(503 if self.path == "/failure" else 200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 9124), Handler)
print("ready", flush=True)
server.serve_forever()
