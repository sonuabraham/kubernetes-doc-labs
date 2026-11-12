# Resource Quotas – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/policy/resource-quotas/

> Docs manifests are **verbatim**: [compute-resources.yaml](compute-resources.yaml) and [object-counts.yaml](object-counts.yaml) (from the page's `cat <<EOF` blocks), [quota.yaml](quota.yaml), [high-priority-pod.yaml](high-priority-pod.yaml), [priority-class-resourcequota.yaml](priority-class-resourcequota.yaml), [disable-cross-namespace-affinity.yaml](disable-cross-namespace-affinity.yaml), two `AdmissionConfiguration`s (`admission-config-*.yaml`, which need API-server flags, so they're reference only) and two `scopeSelector` excerpts. [00-priorityclasses.yaml](00-priorityclasses.yaml) creates the PriorityClasses they name.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **ResourceQuota** | Per-namespace **aggregate** limits, enforced at admission (create/update). Exceeding → **403 Forbidden** with the numbers. Existing objects aren't affected by a new quota. |
| **Compute** | `requests.cpu`, `requests.memory`, `limits.cpu`, `limits.memory` (`cpu` = `requests.cpu`), hugepages, extended resources (`requests.nvidia.com/gpu` only). |
| **Must specify** | If a quota tracks a compute resource, Pods **must** set it (or get it from a LimitRange). |
| **Storage** | `requests.storage`, `persistentvolumeclaims`, per class: `<class>.storageclass.storage.k8s.io/requests.storage`; `requests.ephemeral-storage`. |
| **Object counts** | `count/<resource>.<group>` for any namespaced resource, plus legacy names (`pods`, `services.loadbalancers`, `services.nodeports`…). |
| **Scopes** | `Terminating` / `NotTerminating` (activeDeadlineSeconds), `BestEffort` / `NotBestEffort`, `PriorityClass` (scopeSelector), `CrossNamespacePodAffinity`, `VolumeAttributesClass`. A quota then counts only matching objects. |
| **limitedResources** | Admission config: objects matching a scope are **forbidden unless** a matching quota exists, e.g. "cluster-services priority only where a quota allows it". |
| **Capacity** | Quotas aren't tied to cluster capacity. They can add up to more than the cluster has. |

---

## Lab 1 – The docs' compute and object quotas
```bash
cd concepts/policy/resource-quotas
kubectl create namespace myspace
kubectl create -f ./compute-resources.yaml --namespace=myspace
kubectl create -f ./object-counts.yaml --namespace=myspace
kubectl describe quota object-counts --namespace=myspace
#   configmaps  1  10          <- kube-root-ca.crt (the docs show secrets 1: old clusters auto-created SA token Secrets)
#   secrets     0  10
kubectl run nores -n myspace --image=busybox:1.36 -- sleep 3600
#   forbidden: failed quota: compute-resources: must specify limits.cpu for: nores; limits.memory ...; requests.cpu ...
kubectl run ok -n myspace --image=busybox:1.36 --overrides='{"spec":{"containers":[{"name":"ok","image":"busybox:1.36","command":["sleep","3600"],"resources":{"requests":{"cpu":"600m","memory":"256Mi"},"limits":{"cpu":"1","memory":"512Mi"}}}]}}'
# the same again as ok2:
#   exceeded quota: compute-resources, requested: requests.cpu=600m, used: requests.cpu=600m, limited: requests.cpu=1
for i in 1 2 3; do kubectl create svc loadbalancer lb$i -n myspace --tcp=80; done
#   lb3: exceeded quota: object-counts, requested: services.loadbalancers=1, used: services.loadbalancers=2
```

## Lab 2 – Generic `count/<resource>.<group>` (docs)
```bash
kubectl delete quota --all -n myspace ; kubectl delete pod,svc --all -n myspace
kubectl create quota test --hard=count/deployments.apps=2,count/replicasets.apps=4,count/pods=3,count/secrets=4 --namespace=myspace
kubectl create deployment nginx --image=nginx --namespace=myspace --replicas=2
kubectl describe quota --namespace=myspace
#   count/deployments.apps 1/2   count/pods 2/3   count/replicasets.apps 1/4   count/secrets 0/4
kubectl scale deploy nginx -n myspace --replicas=5
kubectl get deploy nginx -n myspace                    # 3/5 - stuck
kubectl get rs -n myspace -o jsonpath='{.items[0].status.conditions[0].message}'
#   pods "nginx-…" is forbidden: exceeded quota: test, requested: count/pods=1, used: count/pods=3, limited: count/pods=3
```
Quota errors on **controller-created** Pods only show up on the ReplicaSet (condition `ReplicaFailure`), not on the Deployment you scaled.

## Lab 3 – Quota per PriorityClass (docs `quota.yaml`)
```bash
kubectl apply -f 00-priorityclasses.yaml ; kubectl create ns pq-demo
kubectl apply -n pq-demo -f quota.yaml -f high-priority-pod.yaml
kubectl describe quota -n pq-demo | grep -E '^Name|memory|pods'
#   pods-high    memory 10Gi/200Gi  pods 1/10      <- only the matching-priority quota counts the Pod
#   pods-low     memory 0/10Gi      pods 0/10
kubectl run low1 -n pq-demo --overrides='{"spec":{"priorityClassName":"low","containers":[{..."requests":{"cpu":"6","memory":"64Mi"}}]}}' ...
#   exceeded quota: pods-low, requested: cpu=6, used: cpu=0, limited: cpu=5
kubectl run nopc -n pq-demo --image=busybox:1.36 -- sleep 3600     # created: no scope matches a Pod without a PriorityClass
```
The docs' [priority-class-resourcequota.yaml](priority-class-resourcequota.yaml) (no `hard`) only does something together with [admission-config-priorityclass.yaml](admission-config-priorityclass.yaml): then `cluster-services` Pods are allowed **only** in namespaces holding such a quota. Without the API-server flag, a `cluster-services` Pod is created anywhere (as measured here).

## Lab 4 – Scopes: BestEffort, Terminating, CrossNamespacePodAffinity
```bash
kubectl create ns scope-demo ; kubectl apply -n scope-demo -f 01-scopes.yaml
for i in 1 2 3; do kubectl run be$i -n scope-demo --image=busybox:1.36 -- sleep 3600; done
#   be3: exceeded quota: besteffort ...                    (no requests = BestEffort; a 10m-request Pod is still fine)
# two Pods with activeDeadlineSeconds:
#   t2: exceeded quota: terminating ...
kubectl create ns foo-ns ; kubectl apply -f disable-cross-namespace-affinity.yaml      # docs: pods: "0" for that scope
# a Pod with podAffinity.namespaces: ["default"]:
#   exceeded quota: disable-cross-namespace-affinity, requested: pods=1, used: pods=0, limited: pods=0
kubectl run plain -n foo-ns --image=busybox:1.36 -- sleep 3600       # created
```

---

## Useful commands
```bash
kubectl get quota -n <ns> ; kubectl describe quota -n <ns>
kubectl create quota <n> --hard=count/pods=10,requests.cpu=2 [--scopes=BestEffort]
kubectl get rs -n <ns> -o jsonpath='{.items[*].status.conditions}'     # where controller quota errors land
```

## Cleanup
```bash
./cleanup.sh
```
