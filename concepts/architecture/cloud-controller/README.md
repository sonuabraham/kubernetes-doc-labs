# Cloud Controller Manager – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/cloud-controller/

> Cluster: the 2-node profile **`arch-lab`** (see [../README.md](../README.md)).
> minikube isn't a cloud, so there's no real cloud-controller-manager (CCM). In this lab you run **`fake-ccm.sh`**, a pretend CCM for the fictional cloud "fakecloud". It has **exactly** the permissions of the docs' ClusterRole, and it does the node and service controller jobs, so you see what a real CCM changes in the cluster.
> ⚠️ Lab 2 sets `spec.providerID` on the arch-lab nodes. That field **can't be changed** once set, so recreate the profile if you need clean nodes.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **CCM** | Control-plane component (beta since v1.11) that holds the **cloud-specific** control loops, so Kubernetes core stays cloud-agnostic. Each cloud ships a plugin implementing the `CloudProvider` Go interface. |
| **How it runs** | A replicated set of processes (usually Pods) in the control plane with leader election, or as an addon. Several controllers in one binary. |
| **Node controller** | Fills in Node objects from the cloud: the server's unique ID (`spec.providerID`), region/zone/instance-type **labels**, addresses. If a node stops responding, it asks the cloud whether the VM still exists and **deletes the Node** if not. (Sometimes split into node + node-lifecycle controllers.) |
| **Route controller** | Sets up cloud routes so pods on different nodes can reach each other, and may allocate pod CIDRs. |
| **Service controller** | For `type: LoadBalancer` Services: creates, updates and deletes cloud LBs and health checks, then writes the address to `status.loadBalancer`. |
| **Kubelet side** | With `--cloud-provider=external`, a node registers with the taint `node.cloudprovider.kubernetes.io/uninitialized:NoSchedule`. The CCM removes it once it has initialized the node. |
| **RBAC** | Nodes `*`, nodes/status patch, services **list/watch**, services/status **patch/update**, events create/patch/update, serviceaccounts create, persistentvolumes get/list/update/watch. |

## The demo app
| File | What |
|---|---|
| [clusterrole.yaml](clusterrole.yaml) | The docs' ClusterRole `cloud-controller-manager`, **verbatim** |
| [00-ccm-identity.yaml](00-ccm-identity.yaml) | ServiceAccount `kube-system/cloud-controller-manager` + ClusterRoleBinding |
| [01-lb-service.yaml](01-lb-service.yaml) | Namespace `ccm-demo`, Deployment `web`, Service `web` of type LoadBalancer |
| [fake-ccm.sh](fake-ccm.sh) | Node + service controller loop, running as that ServiceAccount |

---

## Step 1
```bash
cd concepts/architecture/cloud-controller
kubectl config use-context arch-lab
kubectl get pods -n kube-system | grep -c cloud-controller     # 0 - no CCM on a learning PC (as the docs say)
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDER-ID:.spec.providerID,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone
#   arch-lab       <none>   <none>
#   arch-lab-m02   <none>   <none>
```

## Lab 1 – The CCM's permissions (docs ClusterRole)
```bash
kubectl apply -f clusterrole.yaml -f 00-ccm-identity.yaml
AS=--as=system:serviceaccount:kube-system:cloud-controller-manager
for c in "list services" "watch services" "get services" "patch services" "delete nodes" "create serviceaccounts" "list persistentvolumes" "get secrets"; do
  printf '%-24s %s\n' "$c" "$(kubectl auth can-i $c $AS -A)"; done
kubectl auth can-i patch services --subresource=status $AS -A       # yes
kubectl auth can-i get   services --subresource=status $AS -A       # no
```
Expected: `list/watch services` yes, **`get services` no**, `patch services` (the spec) no, `delete nodes` yes, `create serviceaccounts` yes, `list persistentvolumes` yes, `get secrets` no.
The service controller may **only write status**, never your Service spec. Note the gap: the docs' *text* says `get` on Services, but the ClusterRole YAML only has `list` and `watch`. That's enough for a controller that works from a watch cache.

## Lab 2 – Node controller: initializing nodes
Pretend the worker joined with `--cloud-provider=external`, which adds the "uninitialized" taint:
```bash
kubectl taint node arch-lab-m02 node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule
kubectl apply -f 01-lb-service.yaml
kubectl get pods -n ccm-demo -o wide          # all on arch-lab - the scheduler avoids the uninitialized node
```
Start the fake CCM (terminal 1):
```bash
./fake-ccm.sh
#   node-controller: initialized arch-lab (providerID fakecloud://arch-lab, zone fakecloud-1a)
#   node-controller: initialized arch-lab-m02 (providerID fakecloud://arch-lab-m02, zone fakecloud-1b)
#   node-controller: removed uninitialized taint from arch-lab-m02
```
Terminal 2:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDER-ID:.spec.providerID,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone,TYPE:.metadata.labels.node\\.kubernetes\\.io/instance-type,TAINTS:.spec.taints
#   arch-lab       fakecloud://arch-lab       fakecloud-1a   fake.medium   <none>
#   arch-lab-m02   fakecloud://arch-lab-m02   fakecloud-1b   fake.medium   <none>
kubectl patch node arch-lab-m02 --type=merge -p '{"spec":{"providerID":"other://x"}}'
#   spec.providerID: ... field cannot be modified once set        <- the cloud identity of a node is permanent
```
These zone labels drive zone spreading and the per-zone eviction rules (`../nodes`, `../../scheduling-eviction/topology-spread-constraints`).

## Lab 3 – Service controller: "provisioning" a load balancer
Before the CCM handles it (or with `fake-ccm.sh` stopped):
```bash
kubectl get svc web -n ccm-demo       # EXTERNAL-IP <pending>
```
With `fake-ccm.sh` running:
```bash
kubectl get svc -n ccm-demo -w
#   web   LoadBalancer   10.102.x.x   203.0.113.50   80:30404/TCP     <- status.loadBalancer.ingress filled in
kubectl create service loadbalancer second --tcp=80 -n ccm-demo        # another one -> its own "LB"
kubectl get svc web -n ccm-demo -o jsonpath='{.status.loadBalancer}{"\n"}'
```
`203.0.113.0/24` is a documentation range, so the address isn't actually reachable. On a real cloud it would be the LB's IP. **Real** local alternative: stop fake-ccm, delete the ingress, and run `minikube tunnel -p arch-lab`. minikube then plays the service controller and assigns a reachable IP.

Why `fake-ccm.sh` uses `curl` for the status update:
```bash
kubectl $AS patch svc web -n ccm-demo --subresource=status --type=merge -p '{"status":{"loadBalancer":{"ingress":[{"ip":"1.2.3.4"}]}}}'
#   Forbidden: ... cannot get resource "services/status"     <- kubectl GETs before it PATCHes; the role has no "get"
```
A real CCM (client-go) sends just the PATCH. The script does the same with the ServiceAccount's own token (`kubectl create token`), so it stays inside the docs' RBAC.

## Lab 4 – Node deletion by the cloud (what a real CCM would do)
The node controller's 4th job is: unresponsive node → ask the cloud → VM gone → **delete the Node object**. With fakecloud there's no cloud to ask, so you play the CCM by hand:
```bash
minikube node stop m02 -p arch-lab                       # VM "terminated"
kubectl $AS delete node arch-lab-m02                     # allowed: nodes '*' in the ClusterRole
kubectl get nodes                                        # gone; its pods are deleted by garbage collection
minikube node start m02 -p arch-lab                      # the kubelet re-registers itself (new Node object, no providerID yet)
```
Without a CCM (plain minikube), a dead node stays `NotReady` forever until someone deletes it, because nothing knows the VM is gone.

---

## Useful commands
```bash
kubectl get nodes -L topology.kubernetes.io/region,topology.kubernetes.io/zone,node.kubernetes.io/instance-type
kubectl get nodes -o custom-columns=NAME:.metadata.name,PROVIDER:.spec.providerID
kubectl get svc -A --field-selector spec.type=LoadBalancer
kubectl auth can-i --list --as=system:serviceaccount:kube-system:cloud-controller-manager
```

## Cleanup
```bash
./cleanup.sh       # namespace, RBAC, lab labels/taints (providerID stays - recreate the profile to reset it)
```
