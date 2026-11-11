# Kubernetes Components – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/components/

> The docs page is a map of the parts of a cluster and has no YAML. In this lab you find each component on minikube, watch it do its job, and in one case stop it to see what breaks.
> minikube runs everything on **one node**. That node is both control plane and worker, and its runtime is **containerd**.

## Key ideas (read first)

| Component | Where | Job (from the docs) |
|---|---|---|
| **kube-apiserver** | control plane | The core server that exposes the Kubernetes HTTP API. Every other component and `kubectl` talks **only** to it. |
| **etcd** | control plane | Consistent, highly-available key/value store for all API server data. Only the API server talks to etcd. |
| **kube-scheduler** | control plane | Finds Pods not yet bound to a node and assigns each one a suitable node. It only **decides**, by setting `spec.nodeName`. It doesn't start anything. |
| **kube-controller-manager** | control plane | Runs the controllers (Deployment, ReplicaSet, Node, Job, EndpointSlice…) that turn desired state into actual state. |
| **cloud-controller-manager** | control plane, **optional** | Integrates with the cloud provider: LoadBalancers, node addresses, routes. **minikube has none.** |
| **kubelet** | every node | Makes sure the Pods bound to its node are running, including their containers. It talks to the runtime through CRI. |
| **kube-proxy** | every node, **optional** | Maintains network rules (iptables, ipvs or nftables) that implement Services. Some CNIs replace it. |
| **Container runtime** | every node | Software that runs containers: containerd, CRI-O, and so on. |
| **Addons** | pods in the cluster | Extra features. Examples: **DNS** (CoreDNS, which every cluster should have), the Web UI (Dashboard), resource monitoring (metrics-server) and cluster-level logging. |
| **Static pods** | control plane on kubeadm/minikube | The control plane itself runs as pods that the kubelet starts from files in `/etc/kubernetes/manifests`. The API server shows read-only "mirror pods" for them. |

## The demo app

```
            kubectl ──HTTP──▶ kube-apiserver ◀──────▶ etcd   (/registry/...)
                                ▲      ▲      ▲
            watch/update ───────┘      │      └─────── kube-scheduler (binds Pods to nodes)
       kube-controller-manager         │
   (Deployment→ReplicaSet→Pods)        │ watch Pods for this node
                                    kubelet ──CRI──▶ containerd ──▶ nginx containers
                                    kube-proxy ──▶ iptables rules for Service "web"
                                    CoreDNS (addon) ──▶ web.components-demo.svc.cluster.local
```
[00-demo-app.yaml](00-demo-app.yaml) in namespace `components-demo` contains Deployment `web` (2× nginx), Service `web` and ConfigMap `demo-config`.
`./etcdctl.sh` runs `etcdctl` inside the etcd pod with minikube's certificates.

---

## Step 1 – Deploy the app
```bash
cd concepts/overview/components
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Available deploy/web -n components-demo --timeout=120s
```

## Lab 1 – Find the components
```bash
kubectl get nodes -o wide                        # minikube  Ready  control-plane  ... containerd://2.x
kubectl get pods -n kube-system -o wide
minikube ssh -- ls /etc/kubernetes/manifests     # etcd, kube-apiserver, kube-controller-manager, kube-scheduler
minikube ssh -- systemctl is-active kubelet      # active - the kubelet is a systemd service, NOT a pod
```
Expected `kube-system` pods:

| Pod | Component | Started by |
|---|---|---|
| `etcd-minikube`, `kube-apiserver-minikube`, `kube-controller-manager-minikube`, `kube-scheduler-minikube` | control plane | **kubelet**, from static manifests (owner kind `Node`) |
| `kube-proxy-xxxxx` | node component | DaemonSet |
| `coredns-…` | DNS addon | Deployment |
| `kindnet-xxxxx` | network plugin (CNI) | DaemonSet |
| `storage-provisioner` | minikube addon | bare pod |

Check who owns the control-plane pods:
```bash
kubectl get pods -n kube-system -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind
```
There is **no** cloud-controller-manager. That's the optional component, and minikube isn't a cloud.

## Lab 2 – kube-apiserver: everything is an HTTP call
```bash
kubectl get --raw='/readyz?verbose' | tail -3     # [+]etcd ok ... readyz check passed
kubectl get --raw /version
kubectl get pods -n components-demo -v=6 2>&1 | grep -E 'GET|Response'
#   GET https://192.168.58.2:8443/api/v1/namespaces/components-demo/pods?limit=500 200 OK
```
`kubectl` is just an HTTP client. The kubelet, the scheduler and the controllers use the same API.

## Lab 3 – etcd: where the objects live
```bash
./etcdctl.sh get /registry/configmaps/components-demo/demo-config --print-value-only | strings | head -5
./etcdctl.sh get /registry/deployments --prefix --keys-only | grep -v '^$'
```
Expected:
```
ConfigMap
demo-config
components-demo"
...
/registry/deployments/components-demo/web
/registry/deployments/kube-system/coredns
```
Keys follow the pattern `/registry/<resource>/<namespace>/<name>`. Values are stored as **protobuf**, which is why you need `strings`. **Secrets are stored here as well**, which is why encryption at rest matters.

## Lab 4 – kube-scheduler: who binds Pods to nodes
```bash
kubectl apply -f 01-pod-other-scheduler.yaml -f 02-pod-nodename.yaml
kubectl get pods -n components-demo -o wide
kubectl get events -n components-demo --field-selector involvedObject.name=unscheduled
kubectl get events -n components-demo --field-selector involvedObject.name=prebound
kubectl get events -n components-demo --field-selector reason=Scheduled
```
Expected:
```
prebound      1/1  Running   NODE minikube
unscheduled   0/1  Pending   NODE <none>
```
- `unscheduled` has **no events at all**. It asks for `no-such-scheduler`, so nothing ever looks at it.
- `prebound` has `Pulled/Created/Started` but **no `Scheduled` event**. `nodeName` was set up front, so the scheduler was skipped and the kubelet simply ran it.
- The `web-…` pods have `Scheduled … Successfully assigned components-demo/web-… to minikube` from `default-scheduler`.

## Lab 5 – kube-controller-manager: the reconcile loops
```bash
kubectl get deploy,rs,pods -n components-demo -l app=web
kubectl get pod -n components-demo -l app=web -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{"\n"}'
#   ReplicaSet/web-557577df75   (the Deployment controller made the RS, the RS controller made the pods)
kubectl delete pod -n components-demo -l app=web --wait=false
kubectl get pods -n components-demo -l app=web    # 2 new pods appear immediately
```
Now **stop the controller manager** by moving its static manifest away. The kubelet notices and stops the pod:
```bash
minikube ssh -- sudo mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/
kubectl get pods -n kube-system | grep controller-manager    # gone after ~20s
kubectl scale deploy web -n components-demo --replicas=4
kubectl get deploy web -n components-demo       # READY 2/4 - spec says 4, nothing acts on it
kubectl delete pod -n components-demo -l app=web --wait=false
kubectl get pods -n components-demo -l app=web  # no replacements - nobody is reconciling
```
The API server still accepts the change, because desired state is stored, but no controller makes it real. Put it back:
```bash
minikube ssh -- sudo mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
kubectl get pods -n components-demo -l app=web -w   # 4 pods appear once it is back
```

## Lab 6 – kubelet: keeps the containers on its node running
```bash
minikube ssh -- 'sudo crictl ps --name nginx --pod $(sudo crictl pods --name prebound -q) -q | xargs sudo crictl stop'
kubectl get pod prebound -n components-demo     # RESTARTS 1 - the kubelet restarted the container
minikube ssh -- sudo journalctl -u kubelet --no-pager -n 5
kubectl get lease minikube -n kube-node-lease -o jsonpath='{.spec.renewTime}{"\n"}'   # node heartbeat, renewed every ~10s
```
Stopping a container behind the kubelet's back doesn't stick, because the kubelet keeps comparing the pod spec with what runs. Static pods (Lab 1) are another kubelet job.

## Lab 7 – kube-proxy: Services become iptables rules
```bash
kubectl get cm kube-proxy -n kube-system -o jsonpath='{.data.config\.conf}' | grep '^mode'   # mode: iptables
kubectl get svc web -n components-demo           # CLUSTER-IP 10.96.x.y
minikube ssh -- "sudo iptables -t nat -S | grep 'components-demo/web'"
```
Expected: one `KUBE-SVC-…` chain for the ClusterIP, and one `KUBE-SEP-…` chain per pod with `DNAT --to-destination <pod-ip>:80`. Scale the Deployment and run the command again: kube-proxy rewrites the rules as endpoints change. More on this in `../../services-networking/service`.

## Lab 8 – Container runtime
```bash
kubectl get node minikube -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}{"\n"}'   # containerd://2.x
minikube ssh -- sudo crictl version
minikube ssh -- sudo crictl pods --namespace components-demo
minikube ssh -- sudo crictl ps --name nginx
```
`crictl` speaks the same **CRI** API the kubelet uses. Every pod also has a `pause` "sandbox" container that holds its network namespace (`sudo crictl pods` lists sandboxes).

## Lab 9 – Addons
```bash
kubectl get deploy coredns -n kube-system        # DNS addon
kubectl run dnstest -n components-demo --rm -i --restart=Never --image=busybox:1.36 -- \
  nslookup web.components-demo.svc.cluster.local     # Address: <cluster-ip of web>
minikube addons list | grep -E 'dashboard|metrics-server'
minikube addons enable metrics-server            # Container Resource Monitoring
kubectl top pods -n components-demo              # works after ~1 min
minikube dashboard --url                         # Web UI (Dashboard) - optional
```
Cluster-level logging has no minikube addon. See `../../cluster-administration/logging` for that.

---

## Useful commands
```bash
kubectl get --raw='/livez?verbose'            # API server health checks
kubectl get componentstatuses                 # deprecated, but still shows scheduler/controller-manager/etcd
kubectl cluster-info
minikube ssh -- sudo crictl ps                # containers as the runtime sees them
kubectl logs -n kube-system kube-scheduler-minikube --tail=20
```

## Cleanup
```bash
./cleanup.sh            # restores the controller-manager manifest if it is still in /tmp, deletes components-demo
minikube addons disable metrics-server   # if you enabled it
```
