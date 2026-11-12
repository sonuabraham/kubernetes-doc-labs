#!/usr/bin/env bash
# fill.sh - pre-load the zones:  zone-a: fake-1 full (3 CPU)   zone-b: empty   zone-c: fake-3 and fake-6 get 500m each
f(){ kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Pod
metadata: {name: $1, namespace: tas, labels: {role: filler}}
spec: {nodeName: $2, containers: [{name: c, image: registry.k8s.io/pause:3.8, resources: {requests: {cpu: "$3"}}}]}
Y
}
f filler-a fake-1 3; f filler-c1 fake-3 500m; f filler-c2 fake-6 500m
