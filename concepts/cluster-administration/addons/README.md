# Installing Addons – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/addons/

> The page is a **catalogue** of third-party add-ons (it isn't an endorsement). [inventory.sh](inventory.sh) (read-only) sorts what this cluster actually runs into the page's categories. Several labs in this repo installed or simulated add-ons, linked below.

## Key ideas (read first)

| Category (page) | Examples | In this cluster / repo |
|---|---|---|
| **Networking & NetworkPolicy** | Calico, Cilium, Flannel, Antrea, kindnet, Multus… | **kindnet** (enforces NetworkPolicy, see `../../security/multi-tenancy`) |
| **Service Discovery** | CoreDNS | **CoreDNS** |
| **Visualization & Control** | Dashboard | not installed (`minikube addons enable dashboard`) |
| **Infrastructure** | KubeVirt, node-problem-detector, CSI drivers | **csi-hostpath-driver + snapshot-controller** (storage labs) |
| **Instrumentation** | kube-state-metrics, Prometheus… | **metrics-server**; kube-state-metrics in `../kube-state-metrics` |
| **Legacy** | deprecated/unmaintained add-ons kept in the cluster/addons tree | – |

Add-ons are ordinary workloads (Deployments/DaemonSets, often in kube-system, with high-priority classes) installed by your distribution, Helm, or manifests, and **upgraded separately** from Kubernetes.

---

## Lab – What's installed?
```bash
cd concepts/cluster-administration/addons
./inventory.sh
```
Measured:
```
Core (node proxy)            DaemonSet    kube-proxy
Infrastructure (storage)     DaemonSet    csi-hostpathplugin
Infrastructure (storage)     Deployment   snapshot-controller
Infrastructure (storage)     StatefulSet  csi-hostpath-attacher, csi-hostpath-resizer
Instrumentation              Deployment   metrics-server
Networking & NetworkPolicy   DaemonSet    kindnet
Service Discovery            Deployment   coredns
minikube addons enabled: csi-hostpath-driver default-storageclass metrics-server storage-provisioner volumesnapshots
```
`storage-provisioner` and `default-storageclass` are minikube's own add-ons (a static Pod / the `standard` class), so they don't appear as Deployments.

---

## Useful commands
```bash
minikube addons list ; minikube addons enable|disable <name>
kubectl get deploy,ds,sts -n kube-system
kubectl get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,PRIO:.spec.priorityClassName | grep -E 'critical'
```

## Cleanup
Nothing to clean up.
