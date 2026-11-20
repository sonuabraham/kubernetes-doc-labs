# Kubernetes Getting started – Hands-on Labs

Labs for every page under https://kubernetes.io/docs/setup/ — one folder per page, mirroring the docs URL slugs.
Docs source synced at website commit be58364903 (2026-11-19). YAML from the docs is kept **verbatim**; anything added is marked "not from the docs".

Status: ✅ lab written · ⬜ not yet

- **Learning environment** (`learning-environment/`) – [section page](learning-environment/)  ✅
- **Production environment** (`production-environment/`) – [section page](production-environment/)  ✅
  - ✅ [Container Runtimes](production-environment/container-runtimes/)
  - **Installing Kubernetes with deployment tools** (`production-environment/tools/`) – [section page](production-environment/tools/)  ⬜
    - **Bootstrapping clusters with kubeadm** (`production-environment/tools/kubeadm/`) – [section page](production-environment/tools/kubeadm/)  ⬜
      - ✅ [Installing kubeadm](production-environment/tools/kubeadm/install-kubeadm/)
      - ⬜ [Troubleshooting kubeadm](production-environment/tools/kubeadm/troubleshooting-kubeadm/)
      - ✅ [Creating a cluster with kubeadm](production-environment/tools/kubeadm/create-cluster-kubeadm/)
      - ✅ [Customizing components with the kubeadm API](production-environment/tools/kubeadm/control-plane-flags/)
      - ⬜ [Options for Highly Available Topology](production-environment/tools/kubeadm/ha-topology/)
      - ✅ [Creating Highly Available Clusters with kubeadm](production-environment/tools/kubeadm/high-availability/)
      - ⬜ [Set up a High Availability etcd Cluster with kubeadm](production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/)
      - ✅ [Configuring each kubelet in your cluster using kubeadm](production-environment/tools/kubeadm/kubelet-integration/)
      - ⬜ [Dual-stack support with kubeadm](production-environment/tools/kubeadm/dual-stack-support/)
  - ⬜ [Turnkey Cloud Solutions](production-environment/turnkey-solutions/)
- **Best practices** (`best-practices/`) – [section page](best-practices/)  ⬜
  - ⬜ [Considerations for large clusters](best-practices/cluster-large/)
  - ⬜ [Running in multiple zones](best-practices/multiple-zones/)
  - ⬜ [Validate node setup](best-practices/node-conformance/)
  - ⬜ [Enforcing Pod Security Standards](best-practices/enforcing-pod-security-standards/)
  - ⬜ [PKI certificates and requirements](best-practices/certificates/)

---

## The section page itself: Getting started

Based on: https://kubernetes.io/docs/setup/

The page recommends "to run Kubernetes components as container images wherever that is possible, and to have Kubernetes manage those
components. Components that run containers – notably, the kubelet – can't be included in this category." That's how minikube (kubeadm
underneath) is built, checked on the default cluster:
```bash
kubectl get pods -n kube-system -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image,OWNER:.metadata.ownerReferences[0].kind
#   etcd-minikube                      registry.k8s.io/etcd:3.7.0-0                  Node        <- static Pods (mirror Pods, owner = Node)
#   kube-apiserver-minikube            registry.k8s.io/kube-apiserver:v1.37.0        Node
#   kube-controller-manager-minikube   registry.k8s.io/kube-controller-manager:v1.37.0  Node
#   kube-scheduler-minikube            registry.k8s.io/kube-scheduler:v1.37.0        Node
#   kube-proxy-c8bcn                   registry.k8s.io/kube-proxy:v1.37.0            DaemonSet
#   coredns-559f6c778d-fsjkx           registry.k8s.io/coredns/coredns:v1.14.6       ReplicaSet
minikube ssh -- ls /etc/kubernetes/manifests       # etcd.yaml kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml
minikube ssh -- systemctl is-active kubelet containerd     # active / active   <- the kubelet and the runtime are host services
```
The control plane runs as **static Pods** from `/etc/kubernetes/manifests`, which the kubelet starts itself (see
[tutorials/cluster-management/kubelet-standalone](../tutorials/cluster-management/kubelet-standalone/)). kube-proxy and CoreDNS are ordinary
workloads. Only the kubelet and containerd are systemd services.
