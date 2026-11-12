# Minimal admission webhook (stdlib only) for the lab:
#   /mutate   - adds label webhook.lab/seen=true to Pods (a JSONPatch "add" on ONE field; idempotent)
#   /validate - rejects Pods labelled forbidden=true
#   /slow     - like /validate but sleeps 5s first (to show timeouts and failurePolicy)
import base64, json, ssl, time
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        review = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        req = review["request"]; obj = req.get("object") or {}
        labels = (obj.get("metadata") or {}).get("labels") or {}
        resp = {"uid": req["uid"], "allowed": True}
        path = self.path.split("?")[0]          # the API server calls e.g. /mutate?timeout=5s
        if path == "/mutate":
            ops = []
            if "labels" not in obj["metadata"]: ops.append({"op": "add", "path": "/metadata/labels", "value": {}})
            ops.append({"op": "add", "path": "/metadata/labels/webhook.lab~1seen", "value": "true"})
            resp.update(patchType="JSONPatch", patch=base64.b64encode(json.dumps(ops).encode()).decode())
        if path in ("/validate", "/slow"):
            if path == "/slow": time.sleep(5)
            if labels.get("forbidden") == "true":
                resp.update(allowed=False, status={"code": 403, "message": "label forbidden=true is not allowed (lab webhook)"})
        print(f"{time.strftime('%T')} {self.path} {req['operation']} {req['namespace']}/{obj.get('metadata',{}).get('name') or obj.get('metadata',{}).get('generateName')}", flush=True)
        out = json.dumps({"apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview", "response": resp}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
srv = HTTPServer(("", 8443), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
srv.socket = ctx.wrap_socket(srv.socket, server_side=True); srv.serve_forever()
