# Resource Bin Packing – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/

> The docs' two scheduler configs are **verbatim** ([most-allocated-config.yaml](most-allocated-config.yaml), [requested-to-capacity-ratio-config.yaml](requested-to-capacity-ratio-config.yaml)), plus the shape and resource snippets (`*-excerpt.yaml`). [00-binpack-scheduler.yaml](00-binpack-scheduler.yaml) runs them as **named profiles** of an extra scheduler (the docs' profiles have no `schedulerName`, so they'd replace `default-scheduler`), plus a `ratio-spread` profile using the docs' inverted shape. The fake nodes advertise the docs' `intel.com/foo` / `intel.com/bar`.

## Key ideas (read first)

| Strategy (NodeResourcesFit `scoringStrategy.type`) | Score | Effect |
|---|---|---|
| **LeastAllocated** (default) | more free → higher | **spreads** |
| **MostAllocated** | more used → higher | **bin-packs** (fewer, fuller nodes; good with autoscalers) |
| **RequestedToCapacityRatio** | piecewise-linear `shape` of utilization → score (0–10) | anything in between: `0→0, 100→10` packs, `0→10, 100→0` spreads |
| **resources + weight** | which resources count and how much | e.g. extended resources (GPUs) weight 3–5 |

---

## Step 1
```bash
cd concepts/scheduling-eviction ; ./fake-nodes.sh up 3 ; cd resource-bin-packing
for n in fake-1 fake-2 fake-3; do kubectl patch node $n --subresource=status --type=json -p '[
  {"op":"add","path":"/status/capacity/intel.com~1foo","value":"8"},{"op":"add","path":"/status/capacity/intel.com~1bar","value":"8"},
  {"op":"add","path":"/status/allocatable/intel.com~1foo","value":"8"},{"op":"add","path":"/status/allocatable/intel.com~1bar","value":"8"}]'; done
kubectl apply -f 00-binpack-scheduler.yaml
```
Patch **allocatable** too: the scheduler only looks at allocatable (a real kubelet derives it from capacity).

## Lab – Same 4 Pods, four strategies
Each Pod requests `cpu: 100m` + `intel.com/foo: 2` (nodeSelector `type: fake`). One strategy at a time, Pods created 2s apart:
```
default-scheduler (LeastAllocated cpu/mem):        fake-1 fake-3 fake-2 fake-1     <- spread
most-allocated    (docs, foo/bar weight 3):         fake-1 fake-1 fake-1 fake-1     <- packed: fake-1's 8 foo are full
ratio-binpack     (docs, shape 0→0, 100→10):        fake-1 fake-1 fake-1 fake-1     <- packed
ratio-spread      (docs' inverted shape 0→10, 100→0): fake-1 fake-2 fake-3 fake-1  <- spread
```
The commands:
```bash
for s in default-scheduler most-allocated ratio-binpack ratio-spread; do for i in 1 2 3 4; do
  kubectl run $s-$i -n binpack-demo --image=registry.k8s.io/pause:3.8 --overrides="{\"spec\":{\"schedulerName\":\"$s\",\"nodeSelector\":{\"type\":\"fake\"},\"containers\":[{\"name\":\"c\",\"image\":\"registry.k8s.io/pause:3.8\",\"resources\":{\"requests\":{\"cpu\":\"100m\",\"intel.com/foo\":\"2\"},\"limits\":{\"intel.com/foo\":\"2\"}}}]}}"; sleep 2; done
  echo "$s: $(kubectl get pods -n binpack-demo -l run -o jsonpath="{range .items[?(@.spec.schedulerName==\"$s\")]}{.spec.nodeName} {end}")"
  kubectl get pods -n binpack-demo -l run -o name | xargs -r kubectl delete -n binpack-demo --grace-period=0 --force; sleep 3
done
```
A first attempt created the Pods **before** allocatable had the resources. They all waited, then were placed in one burst, and the results were meaningless. Scoring is per Pod, against the state at that moment.

---

## Useful commands
```bash
kubectl get nodes -l type=fake -o custom-columns=NAME:.metadata.name,FOO:.status.allocatable.intel\\.com/foo
kubectl describe node <n> | sed -n '/Allocated resources/,/Events/p'
```

## Cleanup
```bash
./cleanup.sh       # namespace, RBAC, and the intel.com/* resources on the fake nodes
```
