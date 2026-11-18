#!/usr/bin/env bash
# Delete the throwaway profile and bring the default cluster back.
minikube delete -p force-lab
docker network rm force-lab 2>/dev/null || true   # minikube left this network behind once
minikube start
