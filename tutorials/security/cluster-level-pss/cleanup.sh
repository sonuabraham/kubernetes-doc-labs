#!/usr/bin/env bash
# Cleanup for "Apply Pod Security Standards at the Cluster Level" – docs: kind delete cluster (×2); here the minikube stand-ins.
cd "$(dirname "$0")"
./minikube-instead-of-kind.sh delete
rm -rf /tmp/pss      # only exists if you ran the docs' heredocs / script yourself
