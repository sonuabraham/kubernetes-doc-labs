#!/usr/bin/env bash
kubectl delete namespace cip-demo --ignore-not-found
kubectl delete servicecidr extra-range --ignore-not-found
