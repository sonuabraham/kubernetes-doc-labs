#!/usr/bin/env bash
# Runs 01-no-selector.yaml for ${SECS:-10}s, then STOPS it and reports where the Pods went.
# Without a nodeSelector the scheduler puts some Windows replicas on the Linux node; the kubelet
# rejects them (PodOSNotSupported = phase Failed), the ReplicaSet replaces them, and so on -> a storm.
NS=win-intro; SECS=${SECS:-10}
kubectl apply -f "$(dirname "$0")/01-no-selector.yaml" >/dev/null
i=0; until [ $i -ge "$SECS" ]; do sleep 1; i=$((i+1)); done
kubectl scale deploy win-noselector -n $NS --replicas=0 >/dev/null
echo "after ${SECS}s (node / phase / count):"
kubectl get pods -n $NS -l app=win-noselector --no-headers -o custom-columns=NODE:.spec.nodeName,PHASE:.status.phase | sort | uniq -c
kubectl get events -n $NS --field-selector reason=PodOSNotSupported -o jsonpath="{.items[0].message}{\"\\n\"}"
kubectl delete deploy win-noselector -n $NS --wait=false >/dev/null
kubectl delete pods -n $NS -l app=win-noselector --force --grace-period=0 >/dev/null 2>&1
echo "stopped and deleted"
