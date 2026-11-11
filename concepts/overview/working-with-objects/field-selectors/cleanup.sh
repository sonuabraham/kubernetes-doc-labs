#!/usr/bin/env bash
kubectl delete namespace fieldsel-demo --ignore-not-found
kubectl delete crd shirts.stable.example.com --ignore-not-found
