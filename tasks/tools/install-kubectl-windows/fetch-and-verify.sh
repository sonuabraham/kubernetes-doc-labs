#!/usr/bin/env bash
# Runs the page's download + checksum steps on Linux (where the result can't be executed, but can be
# verified and identified). Files go to ./dl (gitignored). Usage: ./fetch-and-verify.sh [version]
set -e
V=${1:-v1.37.0}; cd "$(dirname "$0")"; mkdir -p dl; cd dl
curl -sLO "https://dl.k8s.io/release/$V/bin/windows/amd64/kubectl.exe"
curl -sLO "https://dl.k8s.io/$V/bin/windows/amd64/kubectl.exe.sha256"        # the page's URL (no /release/)
curl -sLO "https://dl.k8s.io/release/$V/bin/windows/amd64/kubectl-convert.exe"
curl -sLO "https://dl.k8s.io/$V/bin/windows/amd64/kubectl-convert.exe.sha256"
for f in kubectl.exe kubectl-convert.exe; do
  echo "$(cat $f.sha256)  $f" | sha256sum --check               # = CertUtil -hashfile / Get-FileHash on Windows
  file $f | cut -c1-80
done
