#!/usr/bin/env bash
# pods.sh <podgroup> <from> <to> [cpu]  - create Pods <podgroup>-<i> in namespace gang-sched, members of the PodGroup,
# each asking for 3 CPU (one per 4-CPU fake node) and restricted to fake nodes.
for i in $(seq $2 $3); do
cat <<Y | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: $1-$i, namespace: gang-sched, labels: {group: $1}}
spec:
  schedulingGroup: {podGroupName: $1}
  nodeSelector: {type: fake}
  containers: [{name: c, image: registry.k8s.io/pause:3.8, resources: {requests: {cpu: "${4:-3}"}}}]
Y
done
