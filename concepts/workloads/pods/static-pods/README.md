# Static Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/static-pods/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Static Pod** | Managed **directly by the kubelet** of one node from a file in its `staticPodPath`, with no scheduler, no controller, and no API server needed. The kubelet restarts it if it fails. |
| **Main use** | Self-hosted control plane. kubeadm (and minikube) run `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` and `etcd` this way. It works **before** the API server exists. |
| **Mirror Pod** | A read-only copy the kubelet creates in the API: name `<pod>-<nodename>`, annotation `kubernetes.io/config.mirror`, owner kind `Node`. Labels are copied, so selectors work. **Deleting the mirror doesn't stop the static Pod**; the kubelet recreates the mirror. |
| **Limitations** | Can't reference other API objects (ServiceAccount, ConfigMap, Secret). No ephemeral containers. |
| **vs DaemonSet** | For "one Pod per node" use a **DaemonSet**: rollouts, rollbacks and scaling work there. Static Pods only for bootstrapping. |

## The demo app
[static-web.yaml](static-web.yaml) is an nginx static Pod with label `role: myrole`. [static-with-configmap.yaml](static-with-configmap.yaml) is a static Pod that references a ConfigMap, which isn't allowed. [install-static-pod.sh](install-static-pod.sh) copies a file into the node's `/etc/kubernetes/manifests` (or `--remove` takes it out).

---

## Lab 1 – The control plane is static Pods
```bash
cd concepts/workloads/pods/static-pods
minikube ssh -- "sudo grep staticPodPath /var/lib/kubelet/config.yaml"     # staticPodPath: /etc/kubernetes/manifests
minikube ssh -- ls /etc/kubernetes/manifests                                # etcd, kube-apiserver, kube-controller-manager, kube-scheduler
kubectl get pods -n kube-system -o json | jq -r '.items[] | select(.metadata.annotations["kubernetes.io/config.mirror"]) | .metadata.name'
#   etcd-minikube  kube-apiserver-minikube  kube-controller-manager-minikube  kube-scheduler-minikube
```

## Lab 2 – Create your own static Pod
```bash
./install-static-pod.sh static-web.yaml ; sleep 15
kubectl get pod static-web-minikube -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,OWNER:.metadata.ownerReferences[0].kind
#   static-web-minikube   Running   minikube   Node        <- name = <pod>-<node>, owned by the Node
kubectl get pod static-web-minikube -o jsonpath='{.metadata.annotations}{"\n"}'
#   kubernetes.io/config.mirror, kubernetes.io/config.source: file, kubernetes.io/config.hash
kubectl get pods -l role=myrole                              # labels copied to the mirror
```

## Lab 3 – The API can't control it
```bash
kubectl delete pod static-web-minikube
kubectl get pod static-web-minikube                          # back immediately (a NEW mirror)
minikube ssh -- "sudo crictl ps --name '^web\$'"             # same container, CREATED "about a minute ago" - never stopped
kubectl patch pod static-web-minikube -p '{"spec":{"containers":[{"name":"web","image":"nginx:1.26"}]}}'
#   pod/static-web-minikube patched                         <- the API accepts the edit to the MIRROR ...
minikube ssh -- "sudo crictl ps --name '^web\$' -o json" | jq -r '.containers[0].image.image'    # ... but the real container still runs the image from the FILE
kubectl debug static-web-minikube --image=busybox:1.36 -c dbg -- sleep 1
#   Forbidden: static pods do not support ephemeral containers
```
The only way to change a static Pod is to **edit the file** on the node. The kubelet notices and recreates it.

## Lab 4 – No references to API objects
```bash
./install-static-pod.sh static-with-configmap.yaml ; sleep 12
kubectl get pod static-cm-minikube                            # NotFound - not even a mirror
minikube ssh -- "sudo journalctl -u kubelet --since -2min | grep static-with-configmap | tail -1"
#   "Could not process manifest file" err="static pods may not reference configmaps"
```
A static Pod must work when the API server is down, so it can't depend on API objects.

---

## Useful commands
```bash
minikube ssh -- ls /etc/kubernetes/manifests
kubectl get pods -A -o json | jq -r '.items[] | select(.metadata.annotations["kubernetes.io/config.mirror"]) | .metadata.namespace+"/"+.metadata.name'
```

## Cleanup
```bash
./cleanup.sh      # removes both files from the node; the kubelet stops the pods
```
