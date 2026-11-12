# Scheduling Framework – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/

> The page is about writing **plugins** in Go. Its code is kept as [normalize-score-excerpt.go](normalize-score-excerpt.go) and [plugin-api-excerpt.go](plugin-api-excerpt.go) (illustrative, not compilable). Without compiling a custom scheduler, this lab does the next best thing: it reads the **real plugin configuration** of the running scheduler and runs a scheduler whose profiles turn individual **extension points** on and off ([01-fw-scheduler.yaml](01-fw-scheduler.yaml)). Fake nodes: `../fake-nodes.sh up 3`.

## Key ideas (read first)

| Phase | Extension points | Typical built-in plugins |
|---|---|---|
| **Queue** | PreEnqueue, QueueSort, EnqueueExtension / QueueingHint (when to retry) | SchedulingGates, PrioritySort |
| **Scheduling cycle** (one Pod at a time) | PreFilter → **Filter** → PostFilter (only if no node fits) → PreScore → **Score** → NormalizeScore → Reserve → **Permit** | NodeResourcesFit, NodeAffinity, TaintToleration, PodTopologySpread, InterPodAffinity, VolumeBinding, DynamicResources / DefaultPreemption / ImageLocality, BalancedAllocation |
| **Binding cycle** (async, may run in parallel) | WaitOnPermit → PreBind → **Bind** → PostBind | VolumeBinding (PreBind), DefaultBinder |
| **Unreserve** | Rollback when a later step fails | |
| **Configuration** | Per profile: `plugins.<extensionPoint>.enabled/disabled`, `multiPoint`, `pluginConfig` args, score `weight` | |

---

## Lab 1 – What the default scheduler really runs
```bash
cd concepts/scheduling-eviction/scheduling-framework
kubectl apply -f 00-setup.yaml
T=$(kubectl create token fw-scheduler -n fw-demo)
minikube ssh -- "curl -sk -H 'Authorization: Bearer $T' https://127.0.0.1:10259/configz" | \
  jq -r '.componentconfig.profiles[0].plugins.multiPoint.enabled[] | "\(.name)(\(.weight // 0))"' | paste -sd' '
#   SchedulingGates PrioritySort NodeName NodeUnschedulable TaintToleration(3) NodeAffinity(2) NodePorts NodeResourcesFit(1)
#   VolumeRestrictions NodeVolumeLimits VolumeBinding VolumeZone PodTopologySpread(2) InterPodAffinity(2) DynamicResources(2)
#   DefaultPreemption NodeResourcesBalancedAllocation(1) ImageLocality(1) DefaultBinder NodeDeclaredFeatures
```
Each plugin is registered once under **multiPoint** and hooks into every extension point it implements. The number is its **score weight** (see the 300 = 100×3 TaintToleration score in `../kube-scheduler`).

## Lab 2 – Filter: disable TaintToleration
```bash
kubectl apply -f 01-fw-scheduler.yaml ; N="-n fw-demo"
for n in fake-1 fake-2 fake-3; do kubectl taint nodes $n dedicated=gpu:NoSchedule; done
# the same Pod (nodeSelector type=fake) via each scheduler:
#   t-default-scheduler   <none>      <- filtered: untolerated taint
#   t-no-taint-filter     fake-1      <- the Filter extension point no longer checks taints
```

## Lab 3 – Score: ImageLocality
```bash
# 3 × nginx:1.27 (≈70 MB) per scheduler:   default → minikube, fake-3, minikube   image-lover (weight 50) → fake-2, minikube, fake-3
# 4 × python:latest (≈400 MB) per scheduler: ALL 8 → minikube                       (the only node holding the image)
```
ImageLocality's score grows with image size (from a ~23 MB threshold) and shrinks with how few nodes have the image, so for a small image it barely registers, even ×50. For a big image it decides placement **even at the default weight 1**. We couldn't separate the two profiles here, but the plugin's effect is unmistakable.

## Lab 4 – PostFilter: preemption on/off
```bash
kubectl apply -f 02-priority.yaml          # fw-low (10), fw-high (1000)
# low (fw-low, 3 CPU, pinned to the 4-CPU fake-1) is bound first. Then a 3-CPU fw-high Pod:
#   via no-preemption:     <none>, never nominated
#     "0/4 nodes are available: 1 Insufficient cpu, 3 node(s) didn't match Pod's node affinity/selector."   <- no "preemption: ..." part at all
#   via default-scheduler: low DELETING, high NOMINATED fake-1
#     event on low: "Preempted by pod c18b… on node fake-1"
kubectl delete pod low $N --grace-period=0 --force       # the fake node can't finish the eviction for us
kubectl get pod high $N -o custom-columns=NODE:.spec.nodeName      # fake-1
```
More in `../pod-priority-preemption`.

---

## Useful commands
```bash
kubectl get events -A --field-selector reason=FailedScheduling
kubectl get pod <p> -o jsonpath='{.status.nominatedNodeName}'
```

## Cleanup
```bash
./cleanup.sh
```
