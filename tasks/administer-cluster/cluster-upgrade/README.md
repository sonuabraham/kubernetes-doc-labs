# Upgrade A Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/cluster-upgrade/

> The page is an overview: control plane → nodes → clients → manifests. The kubeadm path is done for real in [../kubeadm/kubeadm-upgrade](../kubeadm/kubeadm-upgrade/) and [../kubeadm/upgrading-linux-nodes](../kubeadm/upgrading-linux-nodes/). Here the "Other deployments" path (the deployment tool's own upgrade: `minikube start --kubernetes-version`) takes a throwaway profile **`up-lab`** from **v1.36.0 to v1.37.0** with a workload running. Then the post-upgrade tasks: storage version migration with [storage-version-migration.yaml](storage-version-migration.yaml) (not from the docs), and the docs' `kubectl convert` command on [pod.yaml](pod.yaml).

## Key ideas (read first)

| Step | Notes |
|---|---|
| **Order (manual)** | etcd → kube-apiserver (all) → kube-controller-manager → kube-scheduler → cloud-controller-manager → kubectl → nodes (drain, kubelet, uncordon). Kubelets may lag the API server, never lead it. |
| **One minor at a time** | 1.36 → 1.37. Read the release notes for removed APIs first. |
| **cgroup v1** | The kubelet defaults to `failCgroupV1: true`; nodes must run cgroup v2. |
| **Storage version** | Objects in etcd stay encoded as written. After an upgrade, rewrite them in the current storage version: read + write each object, or create a `StorageVersionMigration` (`storagemigration.k8s.io/v1`). |
| **Manifests** | Removed API versions are rejected. `kubectl convert` (separate plugin) rewrites manifests to a newer `apiVersion`. |
| **Device plugins** | Must support both the old and new device-plugin API before the node's kubelet is upgraded. |

---

## Step 0 – a v1.36 cluster with something running
```bash
cd tasks/administer-cluster/cluster-upgrade
minikube start -p up-lab --memory 2200 --cpus 2 --kubernetes-version v1.36.0 && kubectl config use-context minikube
K="kubectl --context up-lab"
$K version | tail -1                         # Server Version: v1.36.0
$K create deploy web --image=nginx --replicas=2
$K create secret generic before-upgrade --from-literal=k=v
```

## Lab 1 – Upgrade with the deployment tool
```bash
( while true; do $K get --raw /readyz >/dev/null 2>&1 && echo ok || echo FAIL; sleep 2; done ) > /tmp/probe.log &     # availability probe
minikube start -p up-lab --kubernetes-version v1.37.0
kill %1; sort /tmp/probe.log | uniq -c
#   52 FAIL   6 ok      <- ~100 s without an API server: a single control-plane node can't be upgraded without downtime
$K get nodes                                   # up-lab   Ready   control-plane   v1.37.0
$K -n kube-system get po -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
#   kube-apiserver / kube-controller-manager / kube-scheduler   ...:v1.37.0
#   kube-proxy-...   registry.k8s.io/kube-proxy:v1.36.0      <- add-ons are reconciled a little later...
#   coredns-...      registry.k8s.io/coredns/coredns:v1.14.2
#   etcd-up-lab      registry.k8s.io/etcd:3.6.8-0
# ~1 min later:
$K -n kube-system get ds kube-proxy -o jsonpath='{.spec.template.spec.containers[0].image}'     # ...kube-proxy:v1.37.0
$K -n kube-system get deploy coredns -o jsonpath='{.spec.template.spec.containers[0].image}'   # ...coredns:v1.14.6
$K get po -l app=web                          # Running, RESTARTS 1 - the node's runtime/kubelet restarted under them
```
etcd **stayed at 3.6.8**, while a fresh v1.37 cluster runs 3.7.0 and `kubeadm upgrade apply` upgrades it. Each tool decides which components it upgrades, so check every one. The docs' manual order puts etcd **first**.

## Lab 2 – Switch the storage API version (post-upgrade)
```bash
$K get secret before-upgrade -o jsonpath='{.metadata.resourceVersion}{"\n"}'      # 347
$K apply -f storage-version-migration.yaml
$K get storageversionmigration secrets-after-upgrade -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'
#   Running=False Migration completed
#   Succeeded=True Migration completed
$K get secret before-upgrade -o jsonpath='{.metadata.resourceVersion}{"\n"}'      # 347 - unchanged
```
The migrator rewrote every Secret through the API server. Because Secrets are still stored as `v1`, each write produced identical bytes, and the API server skips such no-op writes. Objects whose storage version (or encryption key, see [../encrypt-data](../encrypt-data/)) actually changed **do** get rewritten.

## Lab 3 – Update manifests: `kubectl convert`
`kubectl-convert` is a separate plugin, installed in [../../tools/install-kubectl-linux](../../tools/install-kubectl-linux/):
```bash
KC=../../tools/install-kubectl-linux/bin/kubectl-convert
$KC -f pod.yaml --output-version v1             # the docs' example: prints the Pod with apiVersion v1 to STDOUT
#   apiVersion: v1  kind: Pod  ...              (pod.yaml itself is NOT modified - redirect to keep the result)
$K apply -f ../../tools/install-kubectl-linux/old-ingress.yaml --dry-run=server
#   error: resource mapping not found ... no matches for kind "Ingress" in version "extensions/v1beta1"
$KC -f ../../tools/install-kubectl-linux/old-ingress.yaml --output-version networking.k8s.io/v1
#   apiVersion: networking.k8s.io/v1   kind: Ingress   ...   backend: {service: {name: web, port: {number: 80}}}   pathType: ImplementationSpecific
```

---

## Useful commands
```bash
kubectl version ; kubectl get nodes -o wide
kubectl get storageversionmigrations
kubectl convert -f <file> --output-version <group/version> > new.yaml
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis     # who still uses deprecated APIs
```

## Cleanup
```bash
minikube delete -p up-lab
```
