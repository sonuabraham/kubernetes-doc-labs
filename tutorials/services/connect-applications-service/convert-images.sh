#!/usr/bin/env bash
# NOT from the docs. bprashanth/nginxhttps:1.0 (nginx-secure-app.yaml) and radial/busyboxplus:curl (curlpod.yaml) are Docker
# "schema 1" images; containerd 2.x refuses them ("not implemented: media type application/vnd.docker.distribution.manifest.v1+prettyjws").
# skopeo still reads schema 1: convert each to a docker-archive with a v2 manifest and load it into minikube under the SAME name,
# so the docs' manifests work unchanged (no imagePullPolicy + non-latest tag = IfNotPresent).
set -euo pipefail
OUT=$(mktemp -d)
for IMG in docker.io/bprashanth/nginxhttps:1.0 docker.io/radial/busyboxplus:curl; do
  f=$(echo "$IMG" | tr '/:' '__').tar
  docker run --rm -v "$OUT":/out quay.io/skopeo/stable:v1.20.0 copy docker://$IMG docker-archive:/out/$f:$IMG
  minikube image load "$OUT/$f"
done
rm -rf "$OUT"
minikube ssh -- sudo crictl images | grep -E 'nginxhttps|busyboxplus'
