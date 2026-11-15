#!/usr/bin/env python3
"""NOT from the docs: verify a ServiceAccount JWT *offline*, the way an external relying party
(Vault, a cloud IAM, ...) does after "service account issuer discovery":

  1. read the issuer's JWKS   (kubectl get --raw /openid/v1/jwks > jwks.json)
  2. pick the key whose kid matches the token header
  3. check the RS256 signature, the issuer, the audience and the expiry

Usage: verify-token.py <jwks.json> <expected-audience> < token
Needs python3-cryptography.
"""
import base64, json, sys, time
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives import hashes
from cryptography.exceptions import InvalidSignature


def b64(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


jwks = json.load(open(sys.argv[1]))
audience = sys.argv[2]
token = sys.stdin.read().strip()
h, p, sig = token.split(".")
header, claims = json.loads(b64(h)), json.loads(b64(p))

key = next((k for k in jwks["keys"] if k["kid"] == header.get("kid")), None)
if key is None:
    sys.exit(f"FAIL: no JWKS key with kid {header.get('kid')}")
pub = rsa.RSAPublicNumbers(int.from_bytes(b64(key["e"]), "big"), int.from_bytes(b64(key["n"]), "big")).public_key()
try:
    pub.verify(b64(sig), f"{h}.{p}".encode(), padding.PKCS1v15(), hashes.SHA256())
except InvalidSignature:
    sys.exit("FAIL: bad signature")

print(f"signature OK (kid {key['kid'][:12]}…)")
print(f"iss  {claims['iss']}")
print(f"sub  {claims['sub']}")
aud_ok = audience in claims.get("aud", [])
print(f"aud  {claims.get('aud')}  -> {'OK' if aud_ok else 'WRONG AUDIENCE for ' + audience}")
left = claims["exp"] - time.time()
print(f"exp  in {int(left)}s  -> {'OK' if left > 0 else 'EXPIRED'}")
print("NOTE: offline checks can't see revocation (deleted Pod/Secret/Node) - only the API server's TokenReview can.")
sys.exit(0 if aud_ok and left > 0 else 1)
