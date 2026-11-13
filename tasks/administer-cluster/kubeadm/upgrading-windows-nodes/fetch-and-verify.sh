#!/usr/bin/env bash
# The page's three downloads (kubeadm.exe, kubelet.exe, kube-proxy.exe) for one version, checksum-verified
# and identified on Linux (they can't run here). Files go to ./dl (gitignored).   ./fetch-and-verify.sh [v1.37.0]
set -e
V=${1:-v1.37.0}; cd "$(dirname "$0")"; mkdir -p dl; cd dl
for f in kubeadm.exe kubelet.exe kube-proxy.exe; do
  curl -sSLo $f        "https://dl.k8s.io/$V/bin/windows/amd64/$f"           # = curl.exe -Lo <path-to-$f> ... on Windows
  curl -sSLo $f.sha256 "https://dl.k8s.io/$V/bin/windows/amd64/$f.sha256"
  echo "$(cat $f.sha256)  $f" | sha256sum --check                           # = Get-FileHash / CertUtil -hashfile
  printf '   %s, %s MB, embedded version: %s\n' "$(file -b $f | cut -c1-46)" "$(( $(stat -c %s $f) / 1048576 ))" \
    "$(grep -aoE "$V(\+[0-9a-f]+)?" $f | head -1)"
done
