#!/usr/bin/env bash
# Usage: ./install-static-pod.sh <file.yaml>   -> copy into the node's staticPodPath
#        ./install-static-pod.sh --remove <file.yaml>
if [ "$1" = --remove ]; then minikube ssh -- "sudo rm -f /etc/kubernetes/manifests/$(basename $2)"; echo "removed $2"; exit; fi
minikube cp "$1" "minikube:/tmp/$(basename $1)" >/dev/null
minikube ssh -- "sudo cp /tmp/$(basename $1) /etc/kubernetes/manifests/ && ls /etc/kubernetes/manifests"
