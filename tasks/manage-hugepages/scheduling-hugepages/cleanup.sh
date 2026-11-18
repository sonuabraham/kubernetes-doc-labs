#!/usr/bin/env bash
# Remove the lab's Pods and give the huge pages back to the host (vm.nr_hugepages=0).
D=$(cd "$(dirname "$0")" && pwd)
kubectl delete pod huge-pages-example hugepages-user --ignore-not-found --now
kubectl delete quota hp-quota --ignore-not-found
"$D/hugepages.sh" free
