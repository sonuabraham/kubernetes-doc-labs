#!/usr/bin/env bash
# ./cni-by-hand.sh [profile] - copies node-cni-by-hand.sh to the minikube node and runs it as root.
P=${1:-minikube}; D=$(cd "$(dirname "$0")" && pwd)
minikube cp -p "$P" "$D/node-cni-by-hand.sh" /tmp/node-cni-by-hand.sh >/dev/null
minikube ssh -p "$P" -- "sudo bash /tmp/node-cni-by-hand.sh; sudo rm -f /tmp/node-cni-by-hand.sh"
