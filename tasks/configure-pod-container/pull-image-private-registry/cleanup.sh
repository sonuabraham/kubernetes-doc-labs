#!/usr/bin/env bash
cd "$(dirname "$0")"
kubectl delete pod private-reg private-reg-wrong cached-no-secret cached-with-secret --ignore-not-found --now
kubectl delete secret regcred regcred-wrong --ignore-not-found
kubectl delete namespace awesomeapps private-registry --ignore-not-found
minikube ssh -- "sudo crictl rmi localhost:5000/janedoe/jdoe-private:v1" >/dev/null 2>&1
docker rmi localhost:5000/janedoe/jdoe-private:v1 >/dev/null 2>&1
rm -rf docker-config my-private-reg-pod.yaml
true
