#!/usr/bin/env python3
"""NOT from the docs: a minimal CRD conversion webhook (Python stdlib, HTTPS on :8443, path /crdconvert) for the
docs' example CRD 04-my-versioned-crontab-with-conversion.yaml:

    example.com/v1beta1:  hostPort: "host:port"
    example.com/v1:       host: "host", port: "port"

It answers ConversionReview v1 (and v1beta1) exactly as described on the page: same uid, result Success/Failed,
convertedObjects in request order with apiVersion = desiredAPIVersion. Every review is logged as one line.

Lab switches (environment variables):
  MUTATE_NAME=1  also rename the object (a forbidden mutation) to see the API server reject the conversion
  ADD_LABEL=1    add label converted-by=webhook (an allowed mutation)
"""
import json, os, ssl, sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def log(msg):
    print(msg, flush=True)


def convert(obj, desired):
    src = obj["apiVersion"]
    out = json.loads(json.dumps(obj))
    if src == desired:
        return out
    if src == "example.com/v1beta1" and desired == "example.com/v1":
        hp = out.pop("hostPort", None)
        if hp is not None:
            if ":" not in hp:
                raise ValueError("hostPort could not be parsed into a separate host and port")
            out["host"], out["port"] = hp.rsplit(":", 1)
    elif src == "example.com/v1" and desired == "example.com/v1beta1":
        host, port = out.pop("host", None), out.pop("port", None)
        if host is not None or port is not None:
            out["hostPort"] = f"{host or ''}:{port or ''}"
    else:
        raise ValueError(f"unexpected conversion {src} -> {desired}")
    out["apiVersion"] = desired
    md = out.setdefault("metadata", {})
    if os.environ.get("ADD_LABEL") == "1":
        md.setdefault("labels", {})["converted-by"] = "webhook"
    if os.environ.get("MUTATE_NAME") == "1":
        md["name"] = md.get("name", "") + "-renamed"
    return out


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        review = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        req = review["request"]
        desired = req["desiredAPIVersion"]
        srcs = [f'{o["metadata"].get("name", "?")}@{o["apiVersion"].split("/")[1]}' for o in req["objects"]]
        resp = {"uid": req["uid"]}
        try:
            resp["convertedObjects"] = [convert(o, desired) for o in req["objects"]]
            resp["result"] = {"status": "Success"}
            status = "Success"
        except ValueError as e:
            resp["result"] = {"status": "Failed", "message": str(e)}
            status = f"Failed: {e}"
        log(f'review {review["apiVersion"]} uid={req["uid"][:8]} -> {desired.split("/")[1]} objects={srcs} {status}')
        body = json.dumps({"apiVersion": review["apiVersion"], "kind": "ConversionReview", "response": resp}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # readiness probe
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("/tls/tls.crt", "/tls/tls.key")
srv = HTTPServer(("", 8443), Handler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
log("conversion webhook listening on :8443")
srv.serve_forever()
