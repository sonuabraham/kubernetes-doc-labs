# Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/nodes/

> Cluster: the 2-node minikube profile **`arch-lab`** (control plane `arch-lab` + worker `arch-lab-m02`). See [../README.md](../README.md) for how to start it.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Node** | A VM or physical machine that runs Pods. It has a kubelet, a container runtime and kube-proxy. It's represented by a cluster-scoped **Node object**. |
| **Registration** | (1) The kubelet **self-registers** (`--register-node=true`, the default and preferred way), or (2) you create a Node object by hand (with `--register-node=false` on the kubelet). The control plane then checks whether a healthy kubelet with that **name** exists. Until then the node is ignored, but the object is kept and re-checked until someone deletes it. |
| **Name** | A DNS subdomain. Unique, and it **is** the identity: a rebuilt machine with the same name is assumed to be the same node. To change a node significantly, delete the Node and re-register. |
| **Kubelet flags** | `--kubeconfig`, `--cloud-provider`, `--register-node`, `--register-with-taints`, `--node-ip`, `--node-labels` (set **only at registration**), `--node-status-update-frequency`. |
| **NodeRestriction** | With Node authorization + the NodeRestriction admission plugin, a kubelet may only modify **its own** Node, and can't set restricted labels such as `node-role.kubernetes.io/*`. |
| **Roles** | `node-role.kubernetes.io/<role>` labels (the value is ignored) populate the ROLES column. |
| **cordon** | Marks the node unschedulable: no **new** pods, existing ones stay. DaemonSet pods tolerate it. Use `drain` to also evict. |
| **Status** | Addresses, Conditions (Ready, MemoryPressure, DiskPressure, PIDPressure…), Capacity/Allocatable, Info. |
| **Heartbeats** | (1) updates to `.status`, (2) a **Lease** per node in `kube-node-lease` (cheap, frequent). |
| **Node controller** | Assigns pod CIDRs, syncs with the cloud, and monitors health every 5s (`--node-monitor-period`). An unreachable node → `Ready=Unknown` + `unreachable` taints → pods are evicted after their toleration (**300s by default**). |
| **Eviction rate limits** | `--node-eviction-rate` 0.1/s (1 node per 10s). In unhealthy zones (≥ `--unhealthy-zone-threshold` 0.55): evictions **stop** in clusters ≤ 50 nodes, otherwise they slow to `--secondary-node-eviction-rate` 0.01/s. If every zone is unhealthy, there are **no** evictions (it assumes a control-plane network problem). |
| **Capacity** | The scheduler keeps the **sum of requests** ≤ the node's allocatable. Processes outside the kubelet aren't counted, so reserve resources for them (`system-reserved`). |

## The demo app
[node.json](node.json) is the docs' Node manifest **verbatim** (`10.240.79.157`).
[00-demo-app.yaml](00-demo-app.yaml) is namespace `nodes-demo`, Deployment `web` (4 pods, which spread over both nodes) and DaemonSet `node-agent`. [01-pod-on-ssd-node.yaml](01-pod-on-ssd-node.yaml) is a nodeSelector pod. [02-fast-eviction.yaml](02-fast-eviction.yaml) has 30s tolerations.

---

## Step 1
```bash
cd concepts/architecture/nodes
kubectl config use-context arch-lab
kubectl apply -f 00-demo-app.yaml
kubectl rollout status deploy/web -n nodes-demo
```

## Lab 1 – A Node object without a kubelet (the docs' JSON)
```bash
kubectl apply -f node.json
kubectl get nodes
#   10.240.79.157   Unknown   <none>   4s            <- object exists, no kubelet ever reported
#   arch-lab        Ready     control-plane
#   arch-lab-m02    Ready     <none>
kubectl get node 10.240.79.157 -o json | jq -c '{labels: .metadata.labels, conditions: .status.conditions}'
#   {"labels":{"name":"my-first-k8s-node"},"conditions":null}
kubectl get pods -n nodes-demo -o wide | grep node-agent
#   node-agent-xxxxx   0/1   Pending   <none>        <- the DaemonSet even made a pod for it; it never runs
kubectl delete node 10.240.79.157                   # "you must explicitly delete the Node object" - its DS pod goes too
```

## Lab 2 – Self-registration and NodeRestriction
How the worker's kubelet was started:
```bash
minikube ssh -p arch-lab -n arch-lab-m02 -- "ps -o args= -C kubelet | tr ' ' '\n' | grep -E 'kubeconfig|node-ip|hostname'"
#   --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf
#   --hostname-override=arch-lab-m02       <- becomes the Node name
#   --kubeconfig=/etc/kubernetes/kubelet.conf
#   --node-ip=192.168.67.3
```
Act **as the worker's kubelet**, using its own credentials:
```bash
K='sudo /var/lib/minikube/binaries/v1.37.0/kubectl --kubeconfig /etc/kubernetes/kubelet.conf'
minikube ssh -p arch-lab -n arch-lab-m02 -- "$K label node arch-lab hacked=yes"
#   Forbidden: User "system:node:arch-lab-m02" ... node 'arch-lab-m02' cannot read 'arch-lab', only its own Node object
minikube ssh -p arch-lab -n arch-lab-m02 -- "$K label node arch-lab-m02 node-role.kubernetes.io/worker=worker"
#   Forbidden: ... is not allowed to modify labels: node-role.kubernetes.io/worker
minikube ssh -p arch-lab -n arch-lab-m02 -- "$K label node arch-lab-m02 team=a"
#   node/arch-lab-m02 labeled           <- its own node, unrestricted label: allowed
kubectl label node arch-lab-m02 team-
```
A compromised node can't relabel itself into, say, a "control-plane" pool or tamper with other nodes.

## Lab 3 – Manual administration: roles, labels, nodeSelector
```bash
kubectl label node arch-lab-m02 node-role.kubernetes.io/worker=worker disktype=ssd
kubectl get nodes                                  # arch-lab-m02  ROLES worker
kubectl apply -f 01-pod-on-ssd-node.yaml
kubectl get pod needs-ssd -n nodes-demo -o wide    # runs on arch-lab-m02 - the only node labelled disktype=ssd
```

## Lab 4 – cordon (the docs command)
```bash
kubectl delete -f 01-pod-on-ssd-node.yaml
kubectl cordon arch-lab-m02
kubectl get nodes                                  # arch-lab-m02  Ready,SchedulingDisabled
kubectl get pods -n nodes-demo -o wide             # existing web pods on m02 keep running
kubectl apply -f 01-pod-on-ssd-node.yaml
kubectl get pod needs-ssd -n nodes-demo -o jsonpath='{.status.conditions[0].message}{"\n"}'
#   0/2 nodes are available: 1 node(s) didn't match Pod's node affinity/selector, 1 node(s) were unschedulable.
kubectl rollout restart ds/node-agent -n nodes-demo ; sleep 8
kubectl get pods -n nodes-demo -l app=node-agent -o wide       # DaemonSet pod recreated ON the cordoned node
kubectl get pod -n nodes-demo -l app=node-agent -o json | jq -c '.items[0].spec.tolerations[] | select(.key|test("unschedulable"))'
#   {"effect":"NoSchedule","key":"node.kubernetes.io/unschedulable","operator":"Exists"}   <- added automatically to DS pods
kubectl uncordon arch-lab-m02                      # needs-ssd now starts on m02
```

## Lab 5 – Node status and heartbeats
```bash
kubectl describe node arch-lab-m02 | sed -n '/^Addresses/,/^System Info/p'
kubectl get node arch-lab-m02 -o json | jq '{addresses: .status.addresses, capacity: .status.capacity, allocatable: .status.allocatable, info: (.status.nodeInfo | {kubeletVersion, containerRuntimeVersion, osImage})}'
kubectl get node arch-lab-m02 -o jsonpath='{range .status.conditions[*]}{.type}={.status} heartbeat={.lastHeartbeatTime}{"\n"}{end}'
kubectl get lease arch-lab-m02 -n kube-node-lease -o jsonpath='{.spec.renewTime}{"\n"}'     # run a few times: renewed every ~10s
```
Two heartbeats: the **Lease** is renewed every ~10s and is cheap. The **status** (conditions) is written when something changes, or about every 5 min otherwise.

## Lab 6 – Node controller: a node dies
```bash
kubectl apply -f 02-fast-eviction.yaml ; kubectl rollout status deploy/quick-evict -n nodes-demo
kubectl get pod -n nodes-demo -l app=web -o json | jq -c '.items[0].spec.tolerations'
#   not-ready / unreachable  NoExecute  tolerationSeconds: 300     <- added to every pod: the docs' "5 minutes"
minikube node stop m02 -p arch-lab                 # "unplug" the worker
kubectl get nodes -w                               # Ctrl-C once arch-lab-m02 shows NotReady
kubectl get node arch-lab-m02 -o json | jq -c '{taints: .spec.taints, ready: (.status.conditions[] | select(.type=="Ready") | {status, reason, message})}'
kubectl get pods -n nodes-demo -o wide -w
```
Timeline measured on this lab cluster:
```
+0s    worker stopped
+52s   Ready=Unknown  reason NodeStatusUnknown "Kubelet stopped posting node status."
       taints: node.kubernetes.io/unreachable:NoSchedule  +  node.kubernetes.io/unreachable:NoExecute
+83s   quick-evict pod on m02 -> Terminating, replacement created on arch-lab (30s toleration)
+~5m50s web pods on m02 -> Terminating, replacements on arch-lab (300s default toleration)
```
- The ~50s delay is the node-monitor **grace period**. The controller checks every 5s, but waits that long before declaring the node unreachable.
- Evicted pods show `Terminating` forever while the node is down. Nobody can confirm that the containers stopped.
- This is a 2-node, single-zone cluster, so the zone is 50% unhealthy, just below the 0.55 threshold, and evictions run at the normal rate. In a 1-node cluster (100% unhealthy) the controller would assume a network partition and **not** evict anything.

Bring it back:
```bash
minikube node start m02 -p arch-lab
kubectl wait --for=condition=Ready node/arch-lab-m02 --timeout=180s
kubectl get node arch-lab-m02 -o jsonpath='{.spec.taints}{"\n"}'   # (empty) - taints removed by the node controller
kubectl get pods -n nodes-demo -o wide            # the Terminating pods are finally deleted
```

## Lab 7 – Resource capacity tracking
```bash
kubectl describe node arch-lab-m02 | sed -n '/Allocated resources/,/Events/p'
#   cpu  <sum of requests> (x%)   <- the scheduler compares requests, not real usage
kubectl scale deploy web -n nodes-demo --replicas=40
kubectl get pods -n nodes-demo -l app=web --field-selector status.phase=Pending | head -3
kubectl describe pod -n nodes-demo $(kubectl get pod -n nodes-demo -l app=web --field-selector status.phase=Pending -o name | head -1 | cut -d/ -f2) | tail -2
#   0/2 nodes are available: 2 Insufficient cpu.     (each pod requests 100m; 2 CPUs per node)
kubectl scale deploy web -n nodes-demo --replicas=4
```

## Lab 8 – Node controller settings
```bash
kubectl get pod -n kube-system kube-controller-manager-arch-lab -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep -E 'node|cidr'
#   --allocate-node-cidrs=true  --cluster-cidr=10.244.0.0/16    <- CIDR assignment (the node controller's first job)
kubectl get nodes -o custom-columns=NODE:.metadata.name,POD-CIDR:.spec.podCIDR
```
No `--node-monitor-period`, `--node-eviction-rate` or `--unhealthy-zone-threshold` flags are set, so the defaults from the table above apply.

---

## Useful commands
```bash
kubectl get nodes -o wide ; kubectl describe node <node>
kubectl cordon|uncordon <node> ; kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl label node <node> key=value ; kubectl taint node <node> key=value:NoSchedule
kubectl get leases -n kube-node-lease
minikube node list|stop|start|add -p arch-lab
```

## Cleanup
```bash
./cleanup.sh      # restarts m02 if stopped, uncordons, removes lab labels, deletes the fake Node and nodes-demo
```
