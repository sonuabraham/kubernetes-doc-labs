# Topology Aware Routing – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/topology-aware-routing/

> ⚠️ Needs a **multi-zone** cluster to show the actual effect. On this single-node minikube the EndpointSlice controller refused to assign hints (`TopologyAwareHintsDisabled: Insufficient Node information …`) even after the node was labelled with a zone and region and the controller-manager was restarted. The lab therefore shows **how to enable it and how to read why it's disabled**. The working shape is the docs' [endpointslice-example-hints.yaml](endpointslice-example-hints.yaml).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Goal** | Keep Service traffic **in the client's zone**, for lower latency and less cross-zone cost. |
| **Enable** | Annotation `service.kubernetes.io/topology-mode: Auto` on the Service. |
| **Hints** | The EndpointSlice controller adds `endpoints[].hints.forZones` to EndpointSlices, allocating endpoints to zones **proportionally to allocatable CPU** per zone. |
| **kube-proxy** | Routes only to endpoints hinted for **its** zone, when hints are present. |
| **Works best when** | Traffic is spread evenly across zones and there are **≥ 3 endpoints per zone** (otherwise ~50% chance of no hints). |
| **Safeguards** | No hints if: fewer endpoints than zones; balanced allocation impossible (expected overload too high); **any node lacks a zone label or allocatable CPU**; any endpoint lacks a zone hint (kube-proxy side); a zone with no endpoints. Then routing is cluster-wide. |
| **Constraints** | Not with `internalTrafficPolicy: Local`; capacity isn't measured live; the controller ignores node readiness for allocation. |
| **Alternative** | `spec.trafficDistribution: PreferSameZone` / `PreferSameNode` (see `../service`, Lab 13): simpler, without proportional allocation. |

## The demo app
[endpointslice-example-hints.yaml](endpointslice-example-hints.yaml) is the docs' EndpointSlice with hints, **verbatim** (reference shape). [00-demo-app.yaml](00-demo-app.yaml) is Deployment `web` (3) and Service `web` **annotated `topology-mode: Auto`**, in `tar-demo`.

---

## Lab 1 – Enable it, and read why it's disabled
```bash
cd concepts/services-networking/topology-aware-routing
kubectl get node minikube -o jsonpath='zone={.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}'     # zone=  (none)
kubectl apply -f 00-demo-app.yaml ; kubectl rollout status deploy/web -n tar-demo
kubectl get endpointslice -n tar-demo -l kubernetes.io/service-name=web -o json | jq -c '[.items[0].endpoints[] | {zone, hints}]'
#   [{"zone":null,"hints":null}, ...]
kubectl get events -n tar-demo --field-selector involvedObject.kind=Service -o custom-columns=REASON:.reason,MESSAGE:.message
#   TopologyAwareHintsDisabled   Insufficient Node information: allocatable CPU or zone not specified on one or more nodes, addressType: IPv4
```
The controller tells you, as an **event on the Service**, which safeguard stopped it.

## Lab 2 – Label a zone (what we observed)
```bash
kubectl label node minikube topology.kubernetes.io/zone=zone-a
kubectl rollout restart deploy/web -n tar-demo ; kubectl rollout status deploy/web -n tar-demo
kubectl get endpointslice -n tar-demo -l kubernetes.io/service-name=web -o json | jq -c '[.items[0].endpoints[] | {zone, hints}]'
#   [{"zone":"zone-a","hints":null}, ...]      <- zone now recorded on each endpoint, but still no hints
kubectl get events -n tar-demo --sort-by=.lastTimestamp | grep -i hint | tail -1
#   TopologyAwareHintsDisabled ... (still, on this cluster - also after a controller-manager restart)
```

## Lab 3 – What it looks like on a 3-zone cluster (reference)
With nodes labelled `zone-a/b/c` and ≥ 9 endpoints, each endpoint gets a hint like the docs example:
```yaml
    zone: zone-a
    hints:
      forZones:
        - name: "zone-a"
```
and `kubectl get events` shows `TopologyAwareHintsEnabled`. A quick way to get such a cluster locally is kind with three worker nodes, each labelled with its own `topology.kubernetes.io/zone`.

---

## Useful commands
```bash
kubectl get endpointslices -l kubernetes.io/service-name=<svc> -o yaml | grep -A3 hints
kubectl get events --field-selector reason=TopologyAwareHintsDisabled
kubectl get nodes -L topology.kubernetes.io/zone
```

## Cleanup
```bash
./cleanup.sh       # namespace + node zone/region labels
```
