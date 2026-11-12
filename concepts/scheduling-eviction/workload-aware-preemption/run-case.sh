#!/usr/bin/env bash
# run-case.sh single|all|mixed - fill the 4 fake-node slots with low-priority work, then submit a 2-Pod high-priority
# gang and report which Pods the scheduler marks for deletion.
#   single : low PodGroup "low" (gang 4, disruptionMode single) - 4 Pods
#   all    : same, disruptionMode all
#   mixed  : 2 standalone low Pods + low PodGroup "low" (gang 2, single) - 2 Pods
set -uo pipefail
N="-n wap"; mode=$1
kubectl delete pods,podgroups --all $N --grace-period=0 --force >/dev/null 2>&1; sleep 3
pod(){ # name group(optional) prio
  g=""; [ -n "$2" ] && g="schedulingGroup: {podGroupName: $2},"
  kubectl apply -f - >/dev/null <<Y
apiVersion: v1
kind: Pod
metadata: {name: $1, namespace: wap}
spec: {$g priorityClassName: $3, nodeSelector: {type: fake}, containers: [{name: c, image: registry.k8s.io/pause:3.8, resources: {requests: {cpu: "3"}}}]}
Y
}
pg(){ # name minCount prio disruption
  kubectl apply -f - >/dev/null <<Y
apiVersion: scheduling.k8s.io/v1beta1
kind: PodGroup
metadata: {name: $1, namespace: wap}
spec: {priorityClassName: $3, schedulingPolicy: {gang: {minCount: $2}}, disruptionMode: {$4: {}}}
Y
}
case $mode in
  single|all) pg low 4 wap-low $mode; for i in 1 2 3 4; do pod low-$i low wap-low; done ;;
  mixed) pod lone-1 "" wap-low; pod lone-2 "" wap-low; sleep 2; pg low 2 wap-low single; pod low-1 low wap-low; pod low-2 low wap-low ;;
esac
sleep 6; echo "before: $(kubectl get pods $N -o jsonpath='{range .items[*]}{.metadata.name}={.spec.nodeName} {end}')"
pg high 2 wap-high all; pod high-1 high wap-high; pod high-2 high wap-high; sleep 8
echo "after : $(kubectl get pods $N -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.spec.nodeName}{.status.nominatedNodeName}{" "}{end}')"
echo "victims (deletionTimestamp set): $(kubectl get pods $N -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name} {end}')"
kubectl get events $N --field-selector reason=Preempted -o custom-columns=M:.message --no-headers | sort | uniq -c | head -3
