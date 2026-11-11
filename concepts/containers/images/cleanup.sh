#!/usr/bin/env bash
kubectl delete namespace images-demo awesomeapps --ignore-not-found
minikube ssh -- "sudo crictl rmi localhost:5000/private/busybox:1.0 >/dev/null 2>&1; true"
