# Pod Topology Spread Constraints – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/

> The docs' 3 example Pods are **verbatim** (`one-constraint.yaml`, `two-constraints.yaml`, `one-constraint-with-nodeaffinity.yaml`), plus the page's excerpts and scheduler configs (`*-excerpt.yaml`, `scheduler-*.yaml`). [setup-docs-topology.sh](setup-docs-topology.sh) rebuilds the page's example cluster on **fake nodes**: node1–node4 in zoneA/zoneB (+ node5 in zoneC), using the page's custom label keys `node` and `zone`, with `foo=bar` Pods on node1, node2 and node3.

## Key ideas (read first)

| Field | Meaning |
|---|---|
| **maxSkew** | Max allowed difference in matching Pods between the most and least loaded topology domains (DoNotSchedule), or the strength of the preference (ScheduleAnyway). |
| **topologyKey** | Node label defining domains (zone, hostname…). Nodes **without** the label are not eligible under DoNotSchedule. |
| **whenUnsatisfiable** | `DoNotSchedule` (filter) or `ScheduleAnyway` (score). |
| **labelSelector** | Which Pods are counted (usually the Pod's own app). |
| **minDomains** | With DoNotSchedule: if fewer domains than this are eligible, the global minimum is treated as **0**, which forces spreading into new domains. |
| **matchLabelKeys** | Add the Pod's own label values to the selector (e.g. `pod-template-hash`: spread each rollout separately). |
| **nodeAffinityPolicy / nodeTaintsPolicy** | Whether nodes excluded by affinity/taints count as domains (defaults Honor / Ignore). |
| **Cluster defaults** | Pods without constraints get the scheduler's **built-in** defaults (hostname maxSkew 3, zone maxSkew 5, ScheduleAnyway) or your `defaultConstraints`. |
| **vs anti-affinity** | Anti-affinity is all-or-nothing (≤1 per domain). Spread allows controlled imbalance. |
| **Limits** | Only checked at scheduling time: scale-down can leave things unbalanced (use a descheduler). |

---

## Step 1
```bash
cd concepts/scheduling-eviction/topology-spread-constraints
./setup-docs-topology.sh
#   fake-1 node1 zoneA   fake-2 node2 zoneA   fake-3 node3 zoneB   fake-4 node4 zoneB   fake-5 node5 zoneC
N="-n tsc-demo"
kubectl label node fake-5 zone- node-        # the first two docs examples assume 4 nodes in 2 zones
```

## Lab 1 – The docs' three examples (each run 3×, same result)
| Manifest | Docs prediction | Measured |
|---|---|---|
| [one-constraint.yaml](one-constraint.yaml) (zone, maxSkew 1) | zoneB (node3 or node4) | **fake-4** (node4, the emptiest in zoneB) |
| [two-constraints.yaml](two-constraints.yaml) (+ node, maxSkew 1) | only node4 | **fake-4** |
| [one-constraint-with-nodeaffinity.yaml](one-constraint-with-nodeaffinity.yaml) (zoneC excluded, node5 back) | zoneB, ignoring empty zoneC | **fake-4** |

With node5/zoneC labelled, the first two land on **fake-5**: an empty zone is the minimum, and that's why the docs' setup has only two zones.

## Lab 2 – Conflicting constraints (docs' 3-node scenario)
```bash
# node1 (zoneA): 2 Pods, node2 (zoneA): 1 Pod, node3 (zoneB): 2 Pods; fake-4/5 unlabelled
kubectl apply $N -f two-constraints.yaml
#   0/6 nodes are available: 3 node(s) didn't match pod topology spread constraints,
#   3 node(s) didn't match pod topology spread constraints (missing required label).      <- Pending, as the docs say
kubectl delete pod mypod $N ; kubectl apply $N -f 01-two-constraints-scheduleanyway.yaml
kubectl get pod mypod $N -o jsonpath='{.spec.nodeName}'      # fake-3 - zone rule still enforced, node rule now only a preference
```

## Lab 3 – minDomains
```bash
kubectl apply $N -f 02-mindomains.yaml           # 4 replicas, maxSkew 1, minDomains 3 - only zoneA and zoneB exist
kubectl get pods $N -l app=three-zones -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName
#   2 placed (fake-1 zoneA, fake-3 zoneB), 2 Pending   <- global min treated as 0: max 1 per zone
kubectl label node fake-5 zone=zoneC node=node5
#   ~20s later: all 4 placed (zoneA 2, zoneB 1, zoneC 1)
```

## Lab 4 – Built-in default constraints
```bash
kubectl apply $N -f 03-no-constraints-deploy.yaml      # 6 replicas, NO topologySpreadConstraints
kubectl get pods $N -l app=plain -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
#   1 fake-1  1 fake-2  2 fake-3  1 fake-4  1 fake-5     <- spread anyway; the Pod spec stays empty
```
[scheduler-default-constraints.yaml](scheduler-default-constraints.yaml) / [scheduler-disable-default-constraints.yaml](scheduler-disable-default-constraints.yaml) (docs) replace or disable these defaults in the scheduler config.

---

## Useful commands
```bash
kubectl get nodes -L topology.kubernetes.io/zone,kubernetes.io/hostname
kubectl get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName -l <selector>
kubectl explain pod.spec.topologySpreadConstraints
```

## Cleanup
```bash
./cleanup.sh
```
