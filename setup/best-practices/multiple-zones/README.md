# Running in multiple zones – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/best-practices/multiple-zones/

> A 3-zone kubeadm cluster on the lab machines ([../../production-environment/tools/kubeadm](../../production-environment/tools/kubeadm/)):
> **cp1 = zone-a** (control plane, untainted so it also runs Pods), **w1 = zone-b**, **cp2 = zone-c**, region `lab`. All files are NOT from
> the docs (the page has no examples): [kubeadm-init-zone-a.yaml](kubeadm-init-zone-a.yaml), [statefulset-zones.yaml](statefulset-zones.yaml)
> (the page's "3 replicas of a StatefulSet … in different zones"), [zonal-pv.yaml](zonal-pv.yaml).
>
> **Notes:**
> - "When nodes start up, the kubelet … automatically adds labels … These labels can include zone information": only with a cloud
>   provider. On bare kubeadm nothing sets `topology.kubernetes.io/zone`. Here each kubelet sets it itself at registration
>   (`kubeletExtraArgs: node-labels=topology.kubernetes.io/zone=…`). NodeRestriction allows a kubelet to set that label, unlike `node-role.*`.
> - The page's `NoVolumeZoneConflict` predicate is the **`VolumeZone`** scheduler plugin today. Its message is `node(s) had no available
>   volume zone`. A PV with `nodeAffinity` is checked by `VolumeBinding` instead (`didn't match PersistentVolume's node affinity`).
> - With `whenUnsatisfiable: DoNotSchedule`, a **cordoned** zone still counts as a domain (nodeTaintsPolicy defaults to `Ignore`), so its
>   low Pod count blocks scaling elsewhere.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Control plane | replicas of every component (and etcd) across ≥ 3 zones; the API endpoint needs its own cross-zone LB/DNS |
| Node labels | `topology.kubernetes.io/region`, `topology.kubernetes.io/zone` (normally from the cloud / kubelet) |
| Default spreading | the scheduler spreads ReplicaSet/StatefulSet Pods over nodes and zones by default (soft) |
| `topologySpreadConstraints` | hard or soft spreading per `topologyKey` (zone) |
| `nodeSelector` | pin Pods to a zone manually |
| Zonal volumes | PVs carry the zone (label/nodeAffinity); Pods using them follow the volume |
| Fault recovery | plan for "all zones down": repair Jobs may need tolerations |

## Lab 1 – A 3-zone cluster
```bash
cd setup/best-practices/multiple-zones
M=../../production-environment/tools/kubeadm/machines.sh
minikube stop; docker start kadm-cp2
docker cp kubeadm-init-zone-a.yaml kadm-cp1:/root/; $M x cp1 'kubeadm init --config kubeadm-init-zone-a.yaml'   # + kindnet.yaml
# w1 / cp2: JoinConfiguration with kubeletExtraArgs node-labels=topology.kubernetes.io/region=lab,topology.kubernetes.io/zone=zone-b|zone-c
kubectl get nodes -L topology.kubernetes.io/region,topology.kubernetes.io/zone
#   cp1   Ready   control-plane   lab   zone-a
#   cp2   Ready   <none>          lab   zone-c
#   w1    Ready   <none>          lab   zone-b
```

## Lab 2 – Spreading Pods
```bash
kubectl create deployment spread --image=registry.k8s.io/pause:3.10.2 --replicas=6
#   2 cp1, 2 cp2, 2 w1                    <- default spreading, no constraints needed
kubectl apply -f statefulset-zones.yaml   # maxSkew 1 over topology.kubernetes.io/zone, DoNotSchedule
#   zonal-0 cp2, zonal-1 w1, zonal-2 cp1  <- one per zone
kubectl cordon cp2
kubectl scale sts zonal --replicas=5      # zonal-3 → w1, zonal-4 → cp1   (2/2/1, skew 1: fine)
kubectl scale sts zonal --replicas=6
#   zonal-5   Pending
#   0/3 nodes are available: 1 node(s) were unschedulable, 2 node(s) didn't match pod topology spread constraints.
kubectl uncordon cp2                      # zonal-5 → cp2
```

## Lab 3 – Storage follows the zone
```bash
kubectl apply -f zonal-pv.yaml            # PV disk-zone-b (zone label + nodeAffinity zone-b), PVC data, Pod uses-zonal-disk
kubectl get pod uses-zonal-disk -o wide   # Running on w1 (zone-b) – the scheduler followed the volume
# a Pod with nodeSelector zone-a and the same claim:
#   0/3 nodes are available: 1 node(s) didn't match PersistentVolume's node affinity, 2 node(s) didn't match Pod's node affinity/selector.
# a PV with only the zone label (zone-c), claimed by a Pod pinned to zone-a:
#   0/3 nodes are available: 1 node(s) had no available volume zone, 2 node(s) didn't match Pod's node affinity/selector.   (VolumeZone)
```

## Cleanup
```bash
for m in cp2 w1 cp1; do $M x $m 'kubeadm reset -f'; done; docker stop kadm-cp2
```
