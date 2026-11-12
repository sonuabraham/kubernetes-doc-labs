#!/usr/bin/env bash
# Runs the page's download + checksum steps for BOTH Mac architectures on Linux (the binaries can't run here,
# but can be verified and identified). Files go to ./dl/<arch> (gitignored). Usage: ./fetch-and-verify.sh [version]
set -e
V=${1:-v1.37.0}; cd "$(dirname "$0")"
for A in amd64 arm64; do
  mkdir -p dl/$A; ( cd dl/$A
  for f in kubectl kubectl-convert; do
    curl -sLO "https://dl.k8s.io/release/$V/bin/darwin/$A/$f"
    curl -sLO "https://dl.k8s.io/release/$V/bin/darwin/$A/$f.sha256"
    echo "$(cat $f.sha256)  $f" | sha256sum --check            # = shasum -a 256 --check on macOS
    file $f | cut -c1-80
  done )
done
