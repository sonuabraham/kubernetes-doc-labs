# Considerations for large clusters – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/best-practices/cluster-large/

> A 5,000-node cluster isn't something to build here, but three things on the page can be seen at small scale:
> 1. the **per-node Pod limit** (110), on the default minikube;
> 2. **Event objects in a dedicated etcd**: the page says to do it "using custom tooling", here with a second etcd static Pod and
>    `--etcd-servers-overrides` on a kubeadm machine (cp1 from [../../production-environment/tools/kubeadm](../../production-environment/tools/kubeadm/));
>    files [etcd-events.yaml](etcd-events.yaml) and [kubeadm-config-events.yaml](kubeadm-config-events.yaml) (NOT from the docs);
> 3. **addon resources and priority**, on the default minikube.
>
> **Found:**
> - minikube's own add-ons only partly follow the page's advice to run cluster-essential components with a system PriorityClass:
>   CoreDNS and metrics-server use `system-cluster-critical`, the control plane and kube-proxy `system-node-critical`. **kindnet** (the
>   CNI DaemonSet), the CSI hostpath driver, the snapshot controller and storage-provisioner have **none**. kindnet is the only add-on
>   with limits (`cpu 100m, memory 50Mi`); CoreDNS has `memory: 170Mi`.
> - `kubeadm reset` doesn't know about a custom etcd: `/var/lib/etcd-events` (123 MB here) stayed behind and had to be removed by hand.

## Key ideas (read first)

| Limit (all must hold) | Value |
|---|---|
| Pods per node | 110 (kubelet `maxPods` default) |
| Nodes | 5,000 |
| Pods total | 150,000 |
| Containers total | 300,000 |

| Topic | Advice |
|---|---|
| Cloud quotas | raise instance/CPU/volume/IP/LB/… quotas; add nodes in batches |
| Control plane | 1–2 instances per failure zone; scale vertically first |
| etcd | put Events in a separate etcd (`--etcd-servers-overrides=/events#…`) |
| Add-ons | requests/limits sized for the cluster (VPA recommender, addon-resizer); `system-cluster-critical` / `system-node-critical` |

## Lab 1 – 110 Pods per node (minikube)
```bash
kubectl get node minikube -o jsonpath='{.status.capacity.pods}'       # 110
kubectl get pods -A --field-selector spec.nodeName=minikube --no-headers | wc -l     # 14 (system Pods)
kubectl create deployment filler --image=registry.k8s.io/pause:3.10.2 --replicas=110
#   running 96, pending 14, total on the node 110
kubectl describe pod <a pending filler Pod>
#   0/1 nodes are available: 1 Too many pods. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
kubectl delete deployment filler
```

## Lab 2 – Events in their own etcd (kubeadm machine cp1)
```bash
cd setup/best-practices/cluster-large
K=../../production-environment/tools/kubeadm/machines.sh
docker cp kubeadm-config-events.yaml kadm-cp1:/root/; docker cp etcd-events.yaml kadm-cp1:/root/
$K x cp1 'kubeadm init phase certs all --config kubeadm-config-events.yaml'          # etcd certs first (etcd-events reuses them)
$K x cp1 'mkdir -p /etc/kubernetes/manifests; cp etcd-events.yaml /etc/kubernetes/manifests/'
$K x cp1 'kubeadm init --config kubeadm-config-events.yaml --ignore-preflight-errors=DirAvailable--etc-kubernetes-manifests'
#   [certs] Using existing ca certificate authority … initialized successfully
$K x cp1 'grep -- etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml'
#   - --etcd-servers=https://127.0.0.1:2379
#   - --etcd-servers-overrides=/events#https://127.0.0.1:12379
kubectl -n kube-system get pods | grep etcd       # etcd-cp1, etcd-events-cp1
# keys per etcd (etcdctl … get /registry/<kind> --prefix --keys-only | grep -c):
#   etcd :2379    events: 0    pods: 8   configmaps: 11
#   etcd :12379   events: 43   pods: 0   configmaps: 0        <- only Events
$K x cp1 'kubeadm reset -f; du -sh /var/lib/etcd-events'      # 123M  – not cleaned by reset
$K x cp1 'rm -rf /var/lib/etcd-events'
```

## Lab 3 – Add-on priority and limits (minikube)
```bash
kubectl get pods -A -o custom-columns='NAME:.metadata.name,PRIORITYCLASS:.spec.priorityClassName,LIMITS:.spec.containers[0].resources.limits' --sort-by=.spec.priority
#   csi-hostpath-*, snapshot-controller-*, storage-provisioner   <none>   <none>
#   kindnet-wt5hc                                                 <none>   map[cpu:100m memory:50Mi]
#   metrics-server-…                                              system-cluster-critical   <none>
#   coredns-…                                                     system-cluster-critical   map[memory:170Mi]
#   etcd / kube-apiserver / kube-controller-manager / kube-scheduler / kube-proxy   system-node-critical
kubectl get priorityclass       # system-cluster-critical 2000000000, system-node-critical 2000001000 (both PreemptLowerPriority)
```

## Cleanup
The filler Deployment is deleted in Lab 1; cp1 is reset in Lab 2.
