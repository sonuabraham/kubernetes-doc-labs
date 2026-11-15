#!/usr/bin/env bash
# NOT from the docs. Start the lab registry and push a private image into it:
#   localhost:5000/janedoe/jdoe-private:v1   (a copy of busybox:1.36 that prints a message)
# The push goes from the host's docker through `kubectl port-forward` (docker also allows plain HTTP for localhost).
# docker uses ./docker-config as its config dir, so your own ~/.docker/config.json is not touched.
set -euo pipefail
cd "$(dirname "$0")"
PASS=${PASS:-xxxxxxxxxxx}
kubectl apply -f 00-registry.yaml >/dev/null
kubectl -n private-registry create secret generic registry-htpasswd \
  --from-literal=htpasswd="$(docker run --rm --entrypoint htpasswd httpd:2 -Bbn janedoe "$PASS")" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n private-registry wait --for=condition=Ready pod/registry --timeout=120s >/dev/null
kubectl -n private-registry port-forward pod/registry 5000:5000 >/dev/null 2>&1 & PF=$!
trap 'kill $PF' EXIT; sleep 3
mkdir -p docker-config
printf 'FROM busybox:1.36\nCMD ["sh","-c","echo hello from a private image; sleep 3600"]\n' | docker build -q -t localhost:5000/janedoe/jdoe-private:v1 - >/dev/null
echo "$PASS" | docker --config ./docker-config login localhost:5000 -u janedoe --password-stdin
docker --config ./docker-config push -q localhost:5000/janedoe/jdoe-private:v1
