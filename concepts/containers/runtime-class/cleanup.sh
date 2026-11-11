#!/usr/bin/env bash
kubectl delete namespace runtimeclass-demo --ignore-not-found
kubectl delete runtimeclass myclass sandboxed --ignore-not-found
kubectl label node minikube runtime.example.com/sandbox- >/dev/null 2>&1
./remove-handler.sh
