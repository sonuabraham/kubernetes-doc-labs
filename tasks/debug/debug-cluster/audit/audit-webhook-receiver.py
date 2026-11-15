#!/usr/bin/env python3
"""NOT from the docs: a toy audit webhook backend. Runs ON THE NODE (127.0.0.1:9880). The API server POSTs an
audit.k8s.io/v1 EventList per batch; we append one summary line per batch + the events to /var/log/audit-webhook.jsonl."""
import json, time
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        items = body.get("items", [])
        with open("/var/log/audit-webhook.jsonl", "a") as f:
            f.write(json.dumps({"batch_at": time.strftime("%H:%M:%S"), "kind": body.get("kind"), "events": len(items)}) + "\n")
            for e in items:
                f.write(json.dumps(e) + "\n")
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
HTTPServer(("127.0.0.1", 9880), H).serve_forever()
