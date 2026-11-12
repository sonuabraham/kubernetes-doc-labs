#!/usr/bin/env bash
# Stop the toy candidates, delete the demo namespace, stop the throwaway profile.
for f in .cand-*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; rm -f "$f"; done
rm -f cand-*.log
kubectl --context cle-lab delete ns cle-demo --ignore-not-found 2>/dev/null
minikube stop -p cle-lab
kubectl config use-context minikube
