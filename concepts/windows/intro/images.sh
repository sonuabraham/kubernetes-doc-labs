#!/usr/bin/env bash
# Reads image manifests from the registries (no pull) and prints which OS / Windows build each one is for,
# then compares the Windows builds with the nodes' node.kubernetes.io/windows-build label.
# Needs: docker CLI (manifest inspect), network access.
show(){ printf '%-66s ' "$1"; docker manifest inspect -v "$1" 2>/dev/null | jq -rc \
  'if type=="array" then map(.Descriptor.platform|"\(.os)/\(.architecture)\(if .["os.version"] then " "+.["os.version"] else "" end)")|join(", ") else .Descriptor.platform|"\(.os)/\(.architecture) \(.["os.version"])" end'; }
echo "== pause image (multi-OS manifest list)"
show registry.k8s.io/pause:3.6
show mcr.microsoft.com/oss/kubernetes/pause:3.6
echo "== Windows base images (the build must match the node's build)"
for i in mcr.microsoft.com/windows/nanoserver:ltsc2022 mcr.microsoft.com/windows/nanoserver:ltsc2025 \
         mcr.microsoft.com/windows/servercore:ltsc2022 mcr.microsoft.com/windows/servercore:ltsc2019; do show $i; done
echo "== Node builds"
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build
