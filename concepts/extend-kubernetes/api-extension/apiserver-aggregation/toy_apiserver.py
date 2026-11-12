#!/usr/bin/env python3
"""Toy extension API server for group toys.example.com/v1 (stdlib only, ~100 lines).

Resources (computed on every request - nothing is stored in etcd, i.e. "custom storage"):
  whoamis  (namespaced, list/get)  -> who the aggregator says is calling (X-Remote-User / X-Remote-Group)
  clocks   (cluster,    list/get)  -> the current time in a few time zones

Authentication: the kube-apiserver (aggregator) connects with the FRONT-PROXY client certificate and
passes the already-authenticated user in X-Remote-* headers. We only trust those headers when the TLS
client cert is signed by the requestheader CA and its CN is in requestheader-allowed-names;
otherwise the caller is treated as "system:anonymous" (anyone could send fake headers).

Env: DELAY_FILE (default /tmp/delay) - if it exists, every request sleeps that many seconds.
"""
import json, os, ssl, time, datetime
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

G, V = "toys.example.com", "v1"
ALLOWED = json.loads(os.environ.get("ALLOWED_NAMES", '["front-proxy-client"]'))
ZONES = {"utc": 0, "sydney": 11, "london": 0, "new-york": -5, "kolkata": 5.5}
RESOURCES = [
    {"name": "whoamis", "singularName": "whoami", "namespaced": True, "kind": "WhoAmI", "verbs": ["get", "list"]},
    {"name": "clocks", "singularName": "clock", "namespaced": False, "kind": "Clock", "verbs": ["get", "list"], "shortNames": ["clk"]},
]


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def caller(self):
        cert = self.connection.getpeercert()          # {} / None unless verified against the requestheader CA
        cn = dict(x[0] for x in cert.get("subject", ())).get("commonName") if cert else None
        if cn in ALLOWED:
            return self.headers.get("X-Remote-User"), self.headers.get_all("X-Remote-Group") or [], cn
        return "system:anonymous", [], cn

    def do_GET(self):
        try:
            time.sleep(float(open(os.environ.get("DELAY_FILE", "/tmp/delay")).read().strip() or 0))
        except (FileNotFoundError, ValueError):
            pass
        user, groups, cn = self.caller()
        p = self.path.split("?")[0].rstrip("/")
        log(f"GET {p}  tls-client-cn={cn}  X-Remote-User={self.headers.get('X-Remote-User')}  -> treated as {user}")
        parts = p.split("/")[1:]
        if p == "/healthz" or p == "/readyz":
            self.send_response(200); self.end_headers(); self.wfile.write(b"ok"); return
        if p == "/apis":
            return self.send(200, {"kind": "APIGroupList", "apiVersion": "v1", "groups": [{"name": G,
                "versions": [{"groupVersion": f"{G}/{V}", "version": V}], "preferredVersion": {"groupVersion": f"{G}/{V}", "version": V}}]})
        if p == f"/apis/{G}":
            return self.send(200, {"kind": "APIGroup", "apiVersion": "v1", "name": G,
                "versions": [{"groupVersion": f"{G}/{V}", "version": V}], "preferredVersion": {"groupVersion": f"{G}/{V}", "version": V}})
        if p == f"/apis/{G}/{V}":
            return self.send(200, {"kind": "APIResourceList", "apiVersion": "v1", "groupVersion": f"{G}/{V}", "resources": RESOURCES})
        now = datetime.datetime.now(datetime.timezone.utc)
        if parts[:4] == ["apis", G, V, "clocks"]:
            items = [{"apiVersion": f"{G}/{V}", "kind": "Clock", "metadata": {"name": z},
                      "time": (now + datetime.timedelta(hours=o)).strftime("%Y-%m-%d %H:%M:%S")} for z, o in ZONES.items()]
            if len(parts) == 5:
                hit = [i for i in items if i["metadata"]["name"] == parts[4]]
                return self.send(200, hit[0]) if hit else self.send(404, status(404, f'clocks "{parts[4]}" not found'))
            return self.send(200, {"apiVersion": f"{G}/{V}", "kind": "ClockList", "metadata": {}, "items": items})
        if parts[:3] == ["apis", G, V] and len(parts) >= 6 and parts[3] == "namespaces" and parts[5] == "whoamis":
            me = {"apiVersion": f"{G}/{V}", "kind": "WhoAmI", "metadata": {"name": "me", "namespace": parts[4]},
                  "user": user, "groups": groups, "via": cn or "no client certificate"}
            return self.send(200, me if len(parts) == 7 else {"apiVersion": f"{G}/{V}", "kind": "WhoAmIList", "metadata": {}, "items": [me]})
        self.send(404, status(404, "not found"))


def status(code, msg):
    return {"kind": "Status", "apiVersion": "v1", "status": "Failure", "message": msg, "code": code}


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
ctx.load_verify_locations("/requestheader/requestheader-client-ca-file")
ctx.verify_mode = ssl.CERT_OPTIONAL                     # verify a client cert if one is presented
srv = ThreadingHTTPServer(("0.0.0.0", 8443), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
log(f"serving {G}/{V} on :8443, trusting X-Remote-* only from client certs with CN in {ALLOWED}")
srv.serve_forever()
