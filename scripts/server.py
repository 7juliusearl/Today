#!/usr/bin/env python3
"""Serves the dashboard exactly like `python3 -m http.server`, plus one
extra endpoint: POST /api/refresh writes a timestamp into a flag file that a
fast-polling scheduled task ("refresh-dashboard-on-demand") checks every
couple minutes. If the flag is present, that task does a real
Calendar/Slack/verse refresh immediately instead of waiting for the normal
30-minute cadence — this is what the dashboard's Refresh button calls to get
a near-live update.

The flag file stays in place for the *entire* time a refresh is queued or
running (the on-demand task only deletes it once it has finished writing new
data), so its mere existence — and its content, a unix timestamp of when it
was requested — is also how the front end knows a refresh is already in
flight and shouldn't be triggered again. It's served like any other static
file under data/, so the client just fetches it directly to check.
"""
import http.server
import os
import socketserver
import time

PORT = 4173
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLAG_PATH = os.path.join(REPO_DIR, "data", ".refresh-requested")


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # This server has no CDN and one user — there's no upside to letting
        # the browser cache anything, and real downsides: without this, a
        # plain reload can serve a stale cached copy of data/dashboard.js
        # even after a real refresh just finished writing fresh data,
        # because that script tag's URL never changes on its own.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        if self.path == "/api/refresh":
            with open(FLAG_PATH, "w") as f:
                f.write(str(time.time()))
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
