# Safely Drain a Node – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/

> This runs on a throwaway **2-node** profile **`drain-lab`** (control plane + worker `drain-lab-m02`). The page has no YAML, so the files here are labelled "not from the docs":
> - [01-statefulset-pdb.yaml](01-statefulset-pdb.yaml) builds the page's example: "a StatefulSet with three replicas and a PodDisruptionBudget … `minAvailable: 2`", with the recommended `unhealthyPodEvictionPolicy: AlwaysAllow`.
> - [02-pods-on-drained-node.yaml](02-pods-on-drained-node.yaml) shows the page's note about Pods that still land on a drained node.
> - [eviction.json](eviction.json) is an Eviction object for the API.
>
> **inotify:** stop the default cluster first (`minikube stop`), see [../kubeadm/adding-linux-nodes](../kubeadm/adding-linux-nodes/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`kubectl drain`** | Cordons the node (taint `node.kubernetes.io/unschedulable:NoSchedule`), then **evicts** each Pod through the Eviction API. That respects PDBs and graceful termination, and drain retries evictions a PDB refuses. |
| **DaemonSets** | Need `--ignore-daemonsets`. Their Pods tolerate the unschedulable taint and would be recreated in place anyway, so they keep running until the node is removed. |
| **PDB** | With `minAvailable: 2` of 3 healthy, only 1 Pod may be down at a time, even across several parallel drains. `AlwaysAllow` lets unhealthy Pods be evicted, so a broken app can't block maintenance. |
| **Still lands on the node** | Pods that tolerate `node.kubernetes.io/unschedulable`, and Pods with `spec.nodeName` set (scheduler bypassed). |
| **Afterwards** | Power off / delete the VM, or `kubectl uncordon` if the node stays. Evicted Pods don't move back on their own. |
| **Eviction API** | `POST .../pods/<name>/eviction` with an `Eviction` object returns **201** if allowed and **429 TooManyRequests** if a PDB forbids it. |

---

## Step 0
```bash
cd tasks/administer-cluster/safely-drain-node
minikube stop
minikube start -p drain-lab --nodes 2 --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context drain-lab
kubectl get nodes
#   drain-lab       Ready   control-plane
#   drain-lab-m02   Ready   <none>
kubectl apply -f 01-statefulset-pdb.yaml && kubectl rollout status sts web
kubectl get po -l app=web -o wide
#   web-0  Running  drain-lab-m02      web-1  Running  drain-lab      web-2  Running  drain-lab-m02
kubectl get pdb web-pdb
#   web-pdb   2   N/A   1          <- MIN AVAILABLE 2, ALLOWED DISRUPTIONS 1
```

## Lab 1 – Drain the worker
```bash
kubectl drain --ignore-daemonsets drain-lab-m02
#   node/drain-lab-m02 cordoned
#   Warning: ignoring DaemonSet-managed Pods: kube-system/kindnet-cbvzx, kube-system/kube-proxy-l9kdn
#   evicting pod default/web-2
#   evicting pod default/web-0
#   error when evicting pods/"web-2" -n "default" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
#   pod/web-0 evicted                       <- one at a time: web-2 waits until web-0 is running and ready elsewhere
#   evicting pod default/web-2
#   pod/web-2 evicted
#   node/drain-lab-m02 drained
kubectl get nodes
#   drain-lab-m02   Ready,SchedulingDisabled   <none>
kubectl get po -l app=web -o wide       # all three now on drain-lab
```

## Lab 2 – The Eviction API directly
```bash
kubectl create --raw /api/v1/namespaces/default/pods/web-0/eviction -f eviction.json
#   {"kind":"Status","apiVersion":"v1","metadata":{},"status":"Success","code":201}     <- allowed (1 disruption left)
kubectl patch pdb web-pdb --type=merge -p '{"spec":{"minAvailable":3}}'                  # now 0 disruptions allowed
kubectl create --raw /api/v1/namespaces/default/pods/web-0/eviction -f eviction.json
#   Error from server (TooManyRequests): Cannot evict pod as it would violate the pod's disruption budget.
kubectl patch pdb web-pdb --type=merge -p '{"spec":{"minAvailable":2}}'
```
(Pods recover in seconds here, so 429 only shows with 0 allowed disruptions. During a real slow restart it shows up naturally.)

## Lab 3 – What still runs on a drained node
```bash
kubectl get node drain-lab-m02 -o jsonpath='{.spec.taints}'
#   [{"effect":"NoSchedule","key":"node.kubernetes.io/unschedulable",...}]
kubectl apply -f 02-pods-on-drained-node.yaml
kubectl get po tolerates-unschedulable bound-by-nodename ordinary -o wide
#   tolerates-unschedulable   Running   drain-lab-m02     <- tolerates the cordon taint
#   bound-by-nodename         Running   drain-lab-m02     <- nodeName bypasses scheduling entirely
#   ordinary                  Pending   <none>
kubectl uncordon drain-lab-m02
kubectl get po ordinary -o wide          # Running on drain-lab-m02
kubectl get po -l app=web -o wide        # still all on drain-lab - nothing rebalances by itself
```

---

## Useful commands
```bash
kubectl drain <node> --ignore-daemonsets [--delete-emptydir-data] [--force] [--timeout=5m] [--disable-eviction]
kubectl uncordon <node>
kubectl get pdb -A
kubectl create --raw /api/v1/namespaces/<ns>/pods/<pod>/eviction -f eviction.json
```

## Cleanup
```bash
minikube delete -p drain-lab
minikube start                 # bring the default cluster back
```
