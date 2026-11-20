#!/usr/bin/env bash
# Cleanup for the PSS best-practices lab.
kubectl delete ns pss-multimode pss-pinned pss-probe --ignore-not-found
