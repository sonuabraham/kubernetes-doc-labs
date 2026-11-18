#!/usr/bin/env bash
# NOT from the docs. gcr.io/google-samples/xtrabackup:1.0 is an old Docker "schema 1" image. containerd >= 2.1
# (minikube v1.39, Kubernetes 1.37) and Docker >= 29 refuse to pull it ("media type … manifest.v1+prettyjws is no longer supported").
# skopeo can still read schema 1. This script converts the image to a docker-archive with a v2 manifest and loads
# it into minikube under the SAME name, so the docs' StatefulSet works unchanged (imagePullPolicy IfNotPresent).
set -euo pipefail
IMG=gcr.io/google-samples/xtrabackup:1.0
OUT=$(mktemp -d)
docker run --rm -v "$OUT":/out quay.io/skopeo/stable:v1.20.0 \
  copy docker://$IMG docker-archive:/out/xtrabackup.tar:$IMG
minikube image load "$OUT/xtrabackup.tar"
rm -rf "$OUT"
minikube ssh -- sudo crictl images | grep xtrabackup
