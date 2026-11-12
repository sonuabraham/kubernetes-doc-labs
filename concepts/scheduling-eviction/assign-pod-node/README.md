# Assigning Pods to Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

> All docs manifests are here **verbatim**: the three example Pods (`pod-with-*.yaml`), [redis-cache.yaml](redis-cache.yaml), [web-server.yaml](web-server.yaml), [nodename-pod.yaml](nodename-pod.yaml), [pod-with-topology-labels.yaml](pod-with-topology-labels.yaml), [scheduler-profile-added-affinity.yaml](scheduler-profile-added-affinity.yaml), plus excerpts with `...` (`*-excerpt.yaml`). Nodes: minikube + the shared fake nodes (`../fake-nodes.sh up 3`: fake-1/2/3 in zone-a/b/c). Namespace `apn-demo`.

## Key ideas (read first)

| Mechanism | Meaning |
|---|---|
| **Node labels** | Built-in (`kubernetes.io/hostname`, `topology.kubernetes.io/zone`…) or your own. `node-restriction.kubernetes.io/` labels can't be set by kubelets (NodeRestriction), so they're safe for isolation. |
| **nodeSelector** | Simplest: Pod runs only on nodes with **all** these labels. |
| **Node affinity** | `required…` (filter) / `preferred…` (score, `weight` 1–100). Operators `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt`. `IgnoredDuringExecution`: label changes don't evict. |
| **Per-profile affinity** | `NodeAffinity` plugin `addedAffinity` applies to every Pod of a scheduler profile, invisible in the Pod spec. |
| **Inter-pod (anti-)affinity** | "Place me (not) near Pods matching X" within a `topologyKey` domain (node, zone…). Required or preferred. Expensive in big clusters. |
| **namespaceSelector / namespaces** | Which namespaces' Pods the term looks at (default: the Pod's own). |
| **matchLabelKeys / mismatchLabelKeys** (GA) | Copy the Pod's **own** label values into the selector (`In` / `NotIn`), e.g. `pod-template-hash` for per-rollout affinity, or per-tenant pools. |
| **nodeName** | Bypasses the scheduler entirely. A missing node → the Pod is orphaned and garbage-collected. |
| **nominatedNodeName** | Where the scheduler *intends* to place the Pod (preemption, or `NominatedNodeNameForExpectation` beta). |
| **Pod topology labels** (`PodTopologyLabelsAdmission`, beta) | On binding, the node's zone/region labels are copied onto the Pod, so the downward API can read them. |

---

## Lab 1 – Node affinity (docs)
```bash
cd concepts/scheduling-eviction ; ./fake-nodes.sh up 3 ; cd assign-pod-node
kubectl create ns apn-demo ; N="-n apn-demo"
kubectl apply $N -f pod-with-node-affinity.yaml
#   0/4 nodes are available: 4 node(s) didn't match Pod's node affinity/selector.     <- no antarctica zones
kubectl label node fake-2 topology.kubernetes.io/zone=antarctica-east1 --overwrite
kubectl get pod with-node-affinity $N -o jsonpath='{.spec.nodeName}'          # fake-2 (retried as the node changed)
kubectl label node fake-1 label-1=key-1 ; kubectl label node fake-3 label-2=key-2
kubectl apply $N -f pod-with-affinity-preferred-weight.yaml
kubectl get pod with-affinity-preferred-weight $N -o jsonpath='{.spec.nodeName}'   # fake-3 (weight 50 beats weight 1)
```

## Lab 2 – Pod affinity (docs `with-pod-affinity`)
```bash
kubectl run s1 $N --image=registry.k8s.io/pause:3.8 --labels=security=S1 --overrides='{"spec":{"nodeName":"fake-1"}}'   # zone-a
kubectl run s2 $N --image=registry.k8s.io/pause:3.8 --labels=security=S2 --overrides='{"spec":{"nodeName":"fake-3"}}'   # zone-c
kubectl apply $N -f pod-with-pod-affinity.yaml
kubectl get pod with-pod-affinity $N -o jsonpath='{.spec.nodeName}'      # fake-1: same zone as S1, away from S2
```

## Lab 3 – Co-locate a cache with web servers (docs redis-cache + web-server)
```bash
kubectl apply $N -f redis-cache.yaml -f web-server.yaml
kubectl get pods $N -l 'app in (store,web-store)' -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName --sort-by=.spec.nodeName
#   redis-cache-…  fake-2     web-server-…  fake-2
#   redis-cache-…  fake-3     web-server-…  fake-3
#   redis-cache-…  minikube   web-server-…  minikube        <- one of each per node, always together
kubectl scale deploy redis-cache $N --replicas=5
#   4 nodes → 4 placed, the 5th: 0/4 nodes are available: 4 node(s) didn't match pod anti-affinity rules.
```

## Lab 4 – Tenants with matchLabelKeys / mismatchLabelKeys
```bash
kubectl label node fake-1 node-pool=pool-1 ; kubectl label node fake-2 fake-3 node-pool=pool-2
for p in "a1 tenant-a" "b1 tenant-b" "a2 tenant-a" "b2 tenant-b"; do set -- $p; sed "s/NAME/$1/; s/TENANT/$2/" 01-tenant-pods.yaml | kubectl apply $N -f -; done
kubectl get pods $N -l tenant -o custom-columns=POD:.metadata.name,TENANT:.metadata.labels.tenant,NODE:.spec.nodeName
#   a1 tenant-a fake-3   a2 tenant-a fake-2    <- tenant-a owns pool-2
#   b1 tenant-b fake-1   b2 tenant-b fake-1    <- tenant-b kept out of pool-2, so pool-1
kubectl get pod a1 $N -o jsonpath='{.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector}'
#   {"matchExpressions":[{"key":"tenant","operator":"In","values":["tenant-a"]}]}     <- matchLabelKeys merged in at creation
```
The first Pod of each tenant defines its pool. After that, no tenant can enter a pool where another runs.

## Lab 5 – nodeName and topology labels
```bash
kubectl apply $N -f nodename-pod.yaml        # nodeName: kube-01 (doesn't exist)
#   nginx  Pending  kube-01                   <- no scheduler involved...
#   gone ~1 min later: the PodGC deletes Pods bound to nonexistent nodes (no event)
kubectl label node minikube topology.kubernetes.io/zone=lab-zone-1 topology.kubernetes.io/region=lab-region
sed 's/name: pod-with-topology-labels/&\n  namespace: apn-demo/' pod-with-topology-labels.yaml | kubectl apply -f -
kubectl get pod pod-with-topology-labels $N -o jsonpath='{.metadata.labels}'
#   {"topology.kubernetes.io/region":"lab-region","topology.kubernetes.io/zone":"lab-zone-1"}   <- copied from the node at binding
kubectl logs pod-with-topology-labels $N | grep MY_        # MY_ZONE=lab-zone-1  MY_REGION=lab-region
```
Every Pod bound to a fake node got `topology.kubernetes.io/zone` too, as you can see with `kubectl get pods $N --show-labels`.

## Lab 6 – Affinity added by a scheduler profile (docs config)
```bash
kubectl apply -f 02-foo-scheduler.yaml      # only the docs' foo-scheduler profile (see the file header)
kubectl run foo1 $N --image=registry.k8s.io/pause:3.8 --overrides='{"spec":{"schedulerName":"foo-scheduler"}}'
#   0/4 nodes are available: 4 node(s) didn't match scheduler-enforced node affinity.
kubectl label node fake-3 scheduler-profile=foo
kubectl delete pod foo1 $N ; kubectl run foo1 ...  # same command
kubectl get pod foo1 $N -o jsonpath='{.spec.nodeName} {.spec.affinity}'      # fake-3, affinity empty: it lives in the profile
```
The Pending `foo1` was **not** retried within 3+ minutes after the label was added (it waits for the unschedulable-queue flush, 5 min), so the lab recreates it.

---

## Useful commands
```bash
kubectl get nodes --show-labels ; kubectl label node <n> key=value
kubectl get pods -o wide ; kubectl get events --field-selector reason=FailedScheduling
kubectl explain pod.spec.affinity.podAffinity.requiredDuringSchedulingIgnoredDuringExecution
```

## Cleanup
```bash
./cleanup.sh       # namespace, scheduler RBAC, all labels added to minikube and the fake nodes
```
