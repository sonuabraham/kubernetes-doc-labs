#!/usr/bin/env python3
"""Replay the DISCOVERY step of "kubeadm join --token T --discovery-token-ca-cert-hash sha256:H" (any OS).
   ./discover.py <server-host:port> <token> <sha256-hash>      -> writes ca.crt next to this script
1. Fetch kube-public/cluster-info WITHOUT trusting the server (anonymous, TLS unverified) - like kubeadm.
2. Token check: the ConfigMap holds jws-kubeconfig-<token-id> = a detached JWS (HS256) of the kubeconfig,
   signed with the token secret. Only someone who knows the token could have produced it.
3. CA pinning: SHA-256 of the CA's public key (DER SubjectPublicKeyInfo) must equal the hash you were given.
Only then is the CA trusted for the TLS bootstrap that follows."""
import base64, hashlib, hmac, json, os, ssl, subprocess, sys, urllib.request

server, token, want = sys.argv[1], sys.argv[2], sys.argv[3].removeprefix("sha256:")
tid, secret = token.split(".")
b64u = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()

ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
url = f"https://{server}/api/v1/namespaces/kube-public/configmaps/cluster-info"
data = json.load(urllib.request.urlopen(url, context=ctx))["data"]
print(f"[discovery] cluster-info keys: {sorted(data)}")

jws = data.get(f"jws-kubeconfig-{tid}")
if not jws:
    sys.exit(f"[discovery] no signature for token id {tid!r} (unknown or expired token) -> join would keep retrying")
header, _, sig = jws.split(".")
expect = b64u(hmac.new(secret.encode(), f"{header}.{b64u(data['kubeconfig'].encode())}".encode(), hashlib.sha256).digest())
if not hmac.compare_digest(sig, expect):
    sys.exit("[discovery] JWS signature mismatch: wrong token secret")
print(f"[discovery] JWS for token {tid} verified (header {base64.urlsafe_b64decode(header + '==').decode()})")

ca_b64 = next(l.split(":", 1)[1].strip() for l in data["kubeconfig"].splitlines() if "certificate-authority-data" in l)
ca_pem = base64.b64decode(ca_b64)
der = subprocess.run("openssl x509 -pubkey -noout | openssl pkey -pubin -outform der", shell=True,
                     input=ca_pem, capture_output=True, check=True).stdout
got = hashlib.sha256(der).hexdigest()
print(f"[discovery] CA public key sha256:{got}")
if got != want:
    sys.exit("[discovery] CA hash does NOT match --discovery-token-ca-cert-hash: refusing to trust this server")
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ca.crt")
open(out, "wb").write(ca_pem)
print(f"[discovery] cluster CA trusted -> {out}")
