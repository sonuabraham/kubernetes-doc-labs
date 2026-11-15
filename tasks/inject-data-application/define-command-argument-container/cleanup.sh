#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f commands.yaml -f snippets.yaml --ignore-not-found --now
