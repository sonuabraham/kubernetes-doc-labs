#!/usr/bin/env bash
kubectl delete namespace controller-demo --ignore-not-found
kubectl delete crd thermostats.home.example.com --ignore-not-found
rm -f "${TMPDIR:-/tmp}"/heater-*
