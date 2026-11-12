#!/usr/bin/env bash
# Remove the demo namespace (plugin DaemonSet included), the plugin's node directory and the image.
kubectl delete ns dp-demo --ignore-not-found
minikube ssh -- 'sudo rm -rf /var/lib/toy-foo'
minikube image rm toy-foo-plugin:1 >/dev/null 2>&1
kubectl get node minikube -o jsonpath='foo capacity={.status.capacity.hardware-vendor\.example/foo} allocatable={.status.allocatable.hardware-vendor\.example/foo}{"\n"}'
