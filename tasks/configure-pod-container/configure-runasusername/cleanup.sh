#!/usr/bin/env bash
kubectl delete pod run-as-username-pod-demo run-as-username-container-demo rau-linux --ignore-not-found --now
