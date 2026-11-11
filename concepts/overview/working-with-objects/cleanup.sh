#!/usr/bin/env bash
# Usage: ./cleanup.sh   -> delete the objects-demo namespace (and everything in it)
kubectl delete namespace objects-demo --ignore-not-found
