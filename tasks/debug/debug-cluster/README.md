# Troubleshooting Clusters – Hands-on Lab (section page)

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/

> The section's landing page: list the nodes, inspect a down node, find the component logs, and know the failure modes.
> Runs on the default **minikube** cluster. The "down node" is an API-only fake node
> ([../../../concepts/scheduling-eviction/fake-nodes.sh](../../../concepts/scheduling-eviction/fake-nodes.sh)) whose heartbeat is stopped.
> The "API server crashing" failure mode is reproduced for ~40 s by [apiserver-down.sh](apiserver-down.sh).
> Not from the docs: [down-node-demo.yaml](down-node-demo.yaml), [apiserver-down.sh](apiserver-down.sh).
> Sub-pages: [troubleshoot-kubectl](troubleshoot-kubectl/), [resource-metrics-pipeline](resource-metrics-pipeline/), [resource-usage-monitoring](resource-usage-monitoring/),
> [monitor-node-health](monitor-node-health/), [crictl](crictl/), [topology](topology/), [audit](audit/), [kubectl-node-debug](kubectl-node-debug/),
> [local-debugging](local-debugging/), [windows](windows/).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Node health** | The kubelet renews its **Lease** and posts node status. If it goes silent for the grace period (~40–50 s), the node controller sets `Ready=Unknown` and adds the `node.kubernetes.io/unreachable` NoSchedule + NoExecute taints. |
| **Eviction** | Pods get a default toleration of 300 s for `unreachable`, then they are evicted. On a really dead node they stay `Terminating` until someone force-deletes them or the node comes back. |
| **Logs** | Static-Pod components (apiserver, scheduler, controller-manager, etcd) log to `/var/log/pods/…` (`kubectl logs -n kube-system …`). The kubelet and container runtime log to journald. The docs' `/var/log/kube-*.log` files don't exist on systemd/kubeadm-style nodes. |
| **API server down** | The control plane stops: no create/update/delete. **The data plane keeps running**: containers, kube-proxy rules, Service traffic. Things that need the API (controllers, operators) fail and restart. |

---

## Step 0 – Listing your cluster (docs)
```bash
cd tasks/debug/debug-cluster
kubectl get nodes                                  # minikube  Ready  control-plane …
kubectl cluster-info dump | wc -c                  # 3240119  <- ~3 MB: every object + every log
kubectl cluster-info dump --namespaces default,kube-system --output-directory=/tmp/cluster-state
ls /tmp/cluster-state /tmp/cluster-state/default
#   default  kube-system  nodes.json
#   daemonsets.json  deployments.json  events.json  pods.json  replicasets.json  replication-controllers.json  services.json
ls /tmp/cluster-state/kube-system/kube-apiserver-minikube      # logs.txt
```
The directory form is what you attach to a bug report, after removing secrets from it.

## Lab 1 – A down/unreachable node (docs example, reproduced)
```bash
../../../concepts/scheduling-eviction/fake-nodes.sh up 1           # fake-1, kept Ready by a heartbeat loop
kubectl apply -f down-node-demo.yaml                               # a Pod on fake-1 tolerating unreachable for 30 s
kill $(cat ../../../concepts/scheduling-eviction/.fake-nodes-minikube.pid)     # stop the heartbeat = "kubelet died"
# poll kubectl get node fake-1 / its taints / the Pod every 5 s:
```
| Time after the last heartbeat | Node | Taints | Pod |
|---|---|---|---|
| t+6 s | Ready | – | Pending (no kubelet ever runs it) |
| t+52 s | **NotReady** | `node.kubernetes.io/unreachable:NoSchedule`, `…:NoExecute` | Pending |
| t+82 s | NotReady | same | **Terminating** (evicted after its 30 s toleration) |
```bash
kubectl describe node fake-1 | sed -n '/^Conditions:/,/^Addresses:/p'
#   Ready  Unknown  …  NodeStatusUnknown  Kubelet stopped posting node status.
kubectl get events --field-selector involvedObject.name=fake-1      # NodeNotReady  Node fake-1 status is now: NodeNotReady
kubectl delete pod on-fake-node --grace-period=0 --force             # nobody will ever confirm the termination
../../../concepts/scheduling-eviction/fake-nodes.sh down
```
With the default 300 s toleration, this is the docs' "evicted after five minutes of NotReady".

## Lab 2 – Looking at logs (docs, adapted to minikube)
```bash
minikube ssh -- 'ls /var/log/kube-*.log'                     # No such file or directory
minikube ssh -- 'sudo ls /var/log/pods | grep -E "kube-|etcd"'
#   kube-system_etcd-minikube_…   kube-system_kube-apiserver-minikube_…   kube-system_kube-controller-manager-minikube_…
#   kube-system_kube-proxy-c8bcn_…   kube-system_kube-scheduler-minikube_…
kubectl logs -n kube-system kube-apiserver-minikube --tail=5       # the same files, via the API
minikube ssh -- 'sudo journalctl -u kubelet -n 20'                  # kubelet: journald
```

## Lab 3 – Failure mode "API server crashing" (not from the docs)
```bash
kubectl create deployment web --image=busybox:1.36 --replicas=2 -- sh -c 'mkdir /w; hostname > /w/index.html; httpd -f -p 8080 -h /w'
kubectl expose deployment web --port=80 --target-port=8080
./apiserver-down.sh
```
```
before:   web-7fddbb4b6c-45282
kubectl:  The connection to the server 192.168.58.2:8443 was refused - did you specify the right host or port?
service:  web-7fddbb4b6c-45282
service:  web-7fddbb4b6c-h4gbz          <- load balancing across both Pods still works (kube-proxy rules are in the kernel)
service:  web-7fddbb4b6c-45282
on node:  2 web Pod sandbox(es) still running
restored: ok
```
Side effect, exactly as the page predicts for things that *depend on the API*: a snapshot-controller replica crashed
(`Failed to list v1 volumesnapshots … dial tcp 10.96.0.1:443`) and went into back-off. It recovered on its own a few minutes later (next back-off retry).

## Failure modes → mitigations (the docs' list, summarised)
| Failure | Effect | Mitigation |
|---|---|---|
| API server down | no changes possible, running workloads continue | HA control plane, automatic VM restart |
| etcd / backing store lost | API server can't start | HA etcd, snapshots ([configure-upgrade-etcd](../../administer-cluster/configure-upgrade-etcd/)) |
| node down / kubelet fault | its Pods stop (or are left alone); NotReady → eviction after 300 s | controllers + Services, apps that tolerate restarts |
| network partition | each side thinks the other is down | multiple zones, sane tolerations |
| operator error | anything | backups, review, RBAC, admission policy |

## Useful commands
```bash
kubectl get nodes -o wide
kubectl describe node <node>
kubectl get leases -n kube-node-lease
kubectl get events -A --field-selector involvedObject.kind=Node
```

## Cleanup
```bash
./cleanup.sh
```
