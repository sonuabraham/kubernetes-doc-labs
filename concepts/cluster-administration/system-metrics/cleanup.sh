#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete -f 01-clusterrole-extra.yaml -f 00-scraper.yaml --ignore-not-found >/dev/null
kubectl delete clusterrole prometheus --ignore-not-found
