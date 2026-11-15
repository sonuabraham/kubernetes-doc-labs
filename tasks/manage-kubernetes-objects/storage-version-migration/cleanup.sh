#!/usr/bin/env bash
# Everything ran on the throwaway profile svm-lab.
minikube -p svm-lab status >/dev/null 2>&1 && minikube delete -p svm-lab
kubectl config use-context minikube 2>/dev/null; true
