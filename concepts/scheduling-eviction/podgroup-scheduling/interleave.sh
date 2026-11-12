#!/usr/bin/env bash
# interleave.sh plain|grouped  - create two 3-Pod "jobs" (3 CPU each, fake nodes only), alternating a-1, b-1, a-2, b-2...
#   plain   : Pods plain-a-*/plain-b-*, no PodGroup (classic Pod-by-Pod scheduling)
#   grouped : Pods a-*/b-*, members of gang PodGroups job-a / job-b (minCount 3)
mode=${1:-plain}
for i in 1 2 3; do for j in a b; do
  if [ "$mode" = plain ]; then name=plain-$j-$i; job=plain-$j; grp=""; else name=$j-$i; job=$j; grp="schedulingGroup: {podGroupName: job-$j},"; fi
  kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Pod
metadata: {name: $name, namespace: pg-sched, labels: {job: $job}}
spec: {$grp nodeSelector: {type: fake}, containers: [{name: c, image: registry.k8s.io/pause:3.8, resources: {requests: {cpu: "3"}}}]}
Y
done; done
