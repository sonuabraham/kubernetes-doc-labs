# Production environment – Section Page (Hands-on)

Based on: https://kubernetes.io/docs/setup/production-environment/

> The section page is a checklist (availability, scale, security, control plane, worker nodes, users, workload limits) with links.
> Below, the default **minikube** is checked against it. A learning cluster fails most production items by design, which makes the
> checklist concrete. Sub-pages: [container-runtimes](container-runtimes/), [tools](tools/) (kubeadm),
> [turnkey-solutions](turnkey-solutions/).
>
> **Found:**
> - The page says the API server "can authenticate users using client certificates, bearer tokens, an authenticating proxy, or **HTTP
>   basic auth**". Basic auth was removed long ago: kube-apiserver v1.37 has no `--basic-auth-file` (`kube-apiserver --help | grep -c
>   basic-auth` → 0). Static tokens (`--token-auth-file`) still exist.
> - "that flag in the ***kube-adminserver.yaml*** file (in */etc/kubernetes/manifests*)": the file is `kube-apiserver.yaml`.

## Key ideas (read first)

| Area | Production asks for | This minikube |
|---|---|---|
| Control plane availability | ≥ 3 control-plane machines, LB in front of the API servers, etcd backed up / separate | 1 node does everything; etcd local (`--etcd-servers=https://127.0.0.1:2379`) |
| Control plane vs workloads | separate control plane from workers | the node has the `node-role.kubernetes.io/control-plane` label but **no** control-plane taint → workloads run there |
| Worker nodes | enough, validated, autoscaled, health-checked | 1 node, no Node Problem Detector |
| Users | real authn (certs/OIDC/…), RBAC per namespace | one admin client cert (`minikube` user) |
| Authorization | `Node,RBAC` (or `--authorization-config`) | `--authorization-mode=Node,RBAC` ✓ |
| Admission | quota, limits, policies | `ResourceQuota`, `LimitRanger` plugins on ✓, but no ResourceQuota/LimitRange objects |
| DNS | scaled for load | CoreDNS **1** replica |

## Lab – Check the cluster
```bash
minikube ssh -- sudo ls /etc/kubernetes/manifests
#   etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml        (no "kube-adminserver.yaml")
minikube ssh -- sudo grep -oE -- '--(authorization-mode|enable-admission-plugins)[^ ]*' /etc/kubernetes/manifests/kube-apiserver.yaml
#   --authorization-mode=Node,RBAC
#   --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,
#                              NodeRestriction,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota
minikube ssh -- 'id=$(sudo crictl ps --name kube-apiserver -q); sudo crictl exec $id kube-apiserver --help | grep -c basic-auth'    # 0
kubectl get node minikube --show-labels | tr ',' '\n' | grep role      # node-role.kubernetes.io/control-plane=   (label, empty value)
kubectl get node minikube -o jsonpath='{.spec.taints}'                   # (empty)  <- no control-plane taint: a single node must run workloads
kubectl -n kube-system get deploy coredns -o jsonpath='{.spec.replicas}'        # 1
kubectl get resourcequota,limitrange -A                                         # No resources found
```
Where each item is practised in this repo:
- control plane HA, etcd: [tools/kubeadm](tools/kubeadm/) (HA topology, HA clusters, HA etcd)
- certificates: [../best-practices/certificates](../best-practices/certificates/)
- node validation: [../best-practices/node-conformance](../best-practices/node-conformance/)
- quotas and limits: [tasks/administer-cluster/manage-resources](../../tasks/administer-cluster/manage-resources/)
- DNS autoscaling: [tasks/administer-cluster/dns-horizontal-autoscaling](../../tasks/administer-cluster/dns-horizontal-autoscaling/)
- user certificates + RBAC: [tasks/tls/certificate-issue-client-csr](../../tasks/tls/certificate-issue-client-csr/)

## Cleanup
Read-only; nothing to clean up.
