#!/usr/bin/env python3
"""Serves the dashboard exactly like `python3 -m http.server`, plus one
extra endpoint: POST /api/refresh touches a flag file that a fast-polling
scheduled task ("refresh-dashboard-on-demand") checks every couple minutes.
If the flag is present, that task does a real Calendar/Slack/verse refresh
immediately instead of waiting for the normal 30-minute cadence — this is
what the dashboard's Refresh button calls to get a near-live update.
"""
import http.server
import os
import socketserver

PORT = 4173
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLAG_PATH = os.path.join(REPO_DIR, "data", ".refresh-requested")


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/api/refresh":
            open(FLAG_PATH, "a").close()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    os.chdir(REPO_DIR)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"Serving {REPO_DIR} on http://localhost:{PORT}")
        httpd.serve_forever()
