#!/usr/bin/env bash
# One -k per command: with several -k flags kubectl only uses the LAST one.
cd "$(dirname "$0")"
kubectl delete -k examples/16-how-to-apply-view-delete-objects-using-kustomize/ --ignore-not-found
kubectl delete -k examples/15-bases-and-overlays/dev/ --ignore-not-found
kubectl delete -k examples/15-bases-and-overlays/prod/ --ignore-not-found
