# Cluster Architecture – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/

> Sub-pages: [nodes](nodes/), [control-plane-node-communication](control-plane-node-communication/), [controller](controller/), [leases](leases/), [cloud-controller](cloud-controller/), [cgroups](cgroups/), [self-healing](self-healing/), [garbage-collection](garbage-collection/), [mixed-version-proxy](mixed-version-proxy/).
> `../overview/components` already finds each component on a single node. **This section uses a 2-node cluster** so you can see the split between control plane and workers.

## Cluster for this section: minikube profile `arch-lab`
```bash
minikube start -p arch-lab --nodes 2 --memory 2200 --cpus 2 --kubernetes-version v1.37.0
kubectl config current-context            # arch-lab  (minikube switches the context for you)
kubectl get nodes -o wide                 # arch-lab (control-plane) + arch-lab-m02 (worker)
```
- Your normal `minikube` profile isn't touched. Switch back at any time with `kubectl config use-context minikube`.
- 3 or more nodes may fail with `Failed to create control group inotify object: Too many open files`. That's the host limit `fs.inotify.max_user_instances` (128 by default). Raise it with `sudo sysctl fs.inotify.max_user_instances=512` if you want more nodes.
- When you're done with the whole section: `./cleanup.sh cluster`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Cluster** | A **control plane** plus **worker nodes**. You need at least one worker to run Pods. In production the control plane runs on several machines (HA) and there are many nodes. |
| **Control plane** | Makes global decisions (scheduling) and reacts to events (a Deployment is short of replicas → start a Pod). Components: kube-apiserver, etcd, kube-scheduler, kube-controller-manager, and optionally cloud-controller-manager. |
| **Controllers (examples)** | **Node** controller (notices dead nodes), **Job** controller (runs Pods to completion), **EndpointSlice** controller (links Services to Pods), **ServiceAccount** controller (a `default` SA in every new namespace). |
| **cloud-controller-manager** | Only controllers specific to a cloud provider: node, route, service (load balancers). **None** on-prem or on a learning PC. |
| **Node components** | kubelet, kube-proxy (optional if the CNI replaces it), container runtime, all on **every** node. |
| **Addons** | Cluster features built from normal resources (DaemonSet, Deployment) in `kube-system`. **DNS** (every cluster should have it), Dashboard, resource monitoring, cluster logging, and **network plugins** (CNI: pod IPs plus pod-to-pod traffic). |
| **Control plane deployment** | Traditional (systemd on dedicated machines), **static Pods** (kubeadm, and minikube), self-hosted (Deployments inside the cluster), or managed (cloud). |
| **Workload placement** | Small clusters mix control plane and workloads. Larger ones keep workloads **off** the control plane, usually with a taint. |

## The demo app
[00-demo-app.yaml](00-demo-app.yaml) is namespace `arch-demo` with Deployment `web` (4× agnhost, which answers `/hostname`) and Service `web`. [01-job.yaml](01-job.yaml) is a one-off Job.

---

## Step 1
```bash
cd concepts/architecture
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Available deploy/web -n arch-demo --timeout=150s
```

## Lab 1 – Control plane vs worker node
```bash
kubectl get nodes -L node-role.kubernetes.io/control-plane
kubectl get pods -n kube-system -o wide --sort-by=.spec.nodeName | awk '{print $1, $7}'
minikube ssh -p arch-lab -n arch-lab     -- ls /etc/kubernetes/manifests    # etcd, kube-apiserver, ...-controller-manager, ...-scheduler
minikube ssh -p arch-lab -n arch-lab-m02 -- ls /etc/kubernetes/manifests    # (empty) - no control plane here
```
Expected:

| Pod | arch-lab (control plane) | arch-lab-m02 (worker) |
|---|---|---|
| etcd, kube-apiserver, kube-controller-manager, kube-scheduler | ✅ (static pods) | – |
| kube-proxy (DaemonSet) | ✅ | ✅ |
| kindnet (network plugin, DaemonSet) | ✅ | ✅ |
| coredns (DNS addon) | ✅ | – |

The control plane exists **once**. Node components and the network plugin run on **every** node.

## Lab 2 – Workload placement
```bash
kubectl get pods -n arch-demo -o wide | awk '{print $1, $7}'
#   pods on BOTH nodes - minikube doesn't taint its control plane (a "small/dev cluster")
kubectl get node arch-lab -o jsonpath='{.spec.taints}{"\n"}'            # (empty)
```
Make it look like a production cluster, where the control plane runs no workloads:
```bash
kubectl taint node arch-lab node-role.kubernetes.io/control-plane:NoSchedule    # what kubeadm sets by default
kubectl rollout restart deploy/web -n arch-demo ; kubectl rollout status deploy/web -n arch-demo
kubectl get pods -n arch-demo -o wide | awk '{print $1, $7}'            # all new pods on arch-lab-m02
kubectl get pods -n kube-system -o wide | grep arch-lab | awk '{print $1, $7}'   # control-plane pods are still there (static pods / tolerations)
kubectl taint node arch-lab node-role.kubernetes.io/control-plane:NoSchedule-   # undo
```
A `NoSchedule` taint only affects **new** pods. Existing pods stay put. More in `../scheduling-eviction/taint-and-toleration`.

## Lab 3 – Controllers named on the page
**Job controller**
```bash
kubectl apply -f 01-job.yaml
kubectl wait --for=condition=Complete job/one-off -n arch-demo ; kubectl logs job/one-off -n arch-demo    # task done on one-off-xxxxx
```
**ServiceAccount controller**
```bash
kubectl create namespace team-x ; kubectl get sa -n team-x       # serviceaccount/default appears immediately
kubectl delete namespace team-x
```
**EndpointSlice controller**
```bash
kubectl get endpointslices -n arch-demo -l kubernetes.io/service-name=web -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.nodeName}{"\n"}{end}'
kubectl scale deploy web -n arch-demo --replicas=2 ; sleep 3     # run the line above again: 2 endpoints
```
**Node controller**: see Lab 4 in [nodes](nodes/), where you stop the worker and watch it go `NotReady`.

## Lab 4 – Network plugin and DNS across nodes
```bash
kubectl get nodes -o custom-columns=NODE:.metadata.name,POD-CIDR:.spec.podCIDR
#   arch-lab       10.244.0.0/24
#   arch-lab-m02   10.244.1.0/24       <- every node gets its own slice for pod IPs (the CNI uses it)
kubectl run c -n arch-demo --restart=Never --image=busybox:1.36 --overrides='{"spec":{"nodeName":"arch-lab"}}' -- \
  sh -c 'grep search /etc/resolv.conf; for i in 1 2 3 4 5 6; do wget -qO- http://web/hostname; echo; done'
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/c -n arch-demo ; kubectl logs c -n arch-demo ; kubectl delete pod c -n arch-demo
```
Expected: `search arch-demo.svc.cluster.local svc.cluster.local cluster.local` (the DNS addon is in every container's search list), then pod names from **both** nodes. The client on `arch-lab` reaches pods in `10.244.1.0/24` on the worker through kindnet.

## Lab 5 – No cloud-controller-manager
```bash
kubectl get pods -n kube-system | grep -c cloud-controller        # 0
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} providerID={.spec.providerID}{"\n"}{end}'
kubectl expose deploy web -n arch-demo --name web-lb --type=LoadBalancer --port=80 --target-port=8080
kubectl get svc web-lb -n arch-demo                                  # EXTERNAL-IP <pending> - no Service (LB) controller from a cloud
```
`minikube tunnel -p arch-lab` plays the cloud's LB role locally. More in [cloud-controller](cloud-controller/).

---

## Useful commands
```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>
kubectl get ds -n kube-system                 # per-node components and addons
minikube ssh -p arch-lab -n <node> -- <cmd>
```

## Cleanup
```bash
./cleanup.sh            # demo namespace, lab taint
./cleanup.sh cluster    # ALSO delete the arch-lab profile and switch back to the "minikube" context (end of section)
```
