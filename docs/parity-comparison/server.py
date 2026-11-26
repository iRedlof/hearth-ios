#!/usr/bin/env python3
"""Parity gallery server with an annotation endpoint.

Serves docs/parity-comparison/ statically AND receives feedback pins the page posts,
appending them to feedback.jsonl so the agent can read them directly (no screenshots).

Run:  python3 docs/parity-comparison/server.py      (http://localhost:8913)
Agent reads:  docs/parity-comparison/feedback.jsonl
"""
import json
import os
import http.server
import socketserver
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
FEEDBACK = os.path.join(HERE, "feedback.jsonl")
DECISIONS = os.path.join(HERE, "decisions.json")   # {id: {choice, title, at}} — the agent reads this
PORT = 8913


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=HERE, **kwargs)

    def _send_json(self, code: int, obj) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _read_feedback(self) -> list:
        items = []
        if os.path.exists(FEEDBACK):
            with open(FEEDBACK) as handle:
                for line in handle:
                    line = line.strip()
                    if line:
                        items.append(json.loads(line))
        return items

    def _read_decisions(self) -> dict:
        if os.path.exists(DECISIONS):
            with open(DECISIONS) as handle:
                return json.load(handle)
        return {}

    def do_GET(self) -> None:
        path = self.path.split("?")[0]
        if path == "/feedback":
            return self._send_json(200, self._read_feedback())
        if path == "/decisions":
            return self._send_json(200, self._read_decisions())
        return super().do_GET()

    def do_POST(self) -> None:
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        if path == "/feedback":
            data = json.loads(raw or b"{}")
            data["at"] = datetime.now().isoformat(timespec="seconds")
            with open(FEEDBACK, "a") as handle:
                handle.write(json.dumps(data) + "\n")
            return self._send_json(200, {"ok": True, "count": len(self._read_feedback())})
        if path == "/feedback/clear":
            open(FEEDBACK, "w").close()
            return self._send_json(200, {"ok": True})
        if path == "/feedback/delete":
            data = json.loads(raw or b"{}")
            idx = data.get("index")
            items = self._read_feedback()
            if isinstance(idx, int) and 0 <= idx < len(items):
                items.pop(idx)
                with open(FEEDBACK, "w") as handle:
                    for item in items:
                        handle.write(json.dumps(item) + "\n")
            return self._send_json(200, {"ok": True, "count": len(items)})
        if path == "/decision":
            data = json.loads(raw or b"{}")
            decisions = self._read_decisions()
            if data.get("id"):
                decisions[data["id"]] = {"choice": data.get("choice"), "title": data.get("title"),
                                         "at": datetime.now().isoformat(timespec="seconds")}
                with open(DECISIONS, "w") as handle:
                    json.dump(decisions, handle, indent=2)
            return self._send_json(200, {"ok": True, "count": len(decisions)})
        return self._send_json(404, {"error": "not found"})

    def log_message(self, *args) -> None:  # quiet
        pass


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"parity server on http://localhost:{PORT}  (feedback -> {FEEDBACK})")
        httpd.serve_forever()
