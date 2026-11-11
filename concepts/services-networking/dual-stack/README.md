# IPv4/IPv6 Dual-Stack – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/dual-stack/

> ⚠️ Your minikube is **single-stack IPv4** (`--service-cluster-ip-range=10.96.0.0/12`, pod CIDR `10.244.0.0/24`). A dual-stack minikube needs **IPv6 enabled in the host's Docker daemon** plus dual CIDRs at cluster creation, which this lab doesn't change on your machine. What you **can** see here is exactly how the API treats the docs' dual-stack manifests on a single-stack cluster, which is what happens when such manifests meet a cluster without dual-stack.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Dual-stack** | Stable since 1.23. Pods and Services can get **both** an IPv4 and an IPv6 address. |
| **Requirements** | Provider/network with routable IPv4+IPv6 interfaces on nodes, a dual-stack CNI, and **two** ranges in `--service-cluster-ip-range`, `--cluster-cidr` (controller-manager) and the kubelet's `--node-ip`. |
| **ipFamilyPolicy** | `SingleStack` (default), `PreferDualStack` (two families if available, else one, **never fails**), `RequireDualStack` (fails unless the cluster is dual-stack). |
| **ipFamilies** | Order matters: the **first** family is the primary (`.spec.clusterIP`). Allowed: `[IPv4]`, `[IPv6]`, `[IPv4,IPv6]`, `[IPv6,IPv4]`. |
| **clusterIPs** | One IP per family. `.spec.clusterIP` = `clusterIPs[0]`. |
| **Existing Services** | Keep their policy. You can switch SingleStack ↔ PreferDualStack/RequireDualStack later. Headless Services without selectors default to `RequireDualStack` on dual-stack clusters. |
| **LoadBalancer** | Needs a dual-stack-capable cloud LB. |
| **Egress** | Pods with IPv6 need routable or NAT'd IPv6 to reach the internet. |

## The demo app
The docs manifests are **verbatim** (all named `my-service`, so each goes into its own namespace):
| File | Spec |
|---|---|
| [dual-stack-default-svc.yaml](dual-stack-default-svc.yaml) | no ipFamily fields → `SingleStack` |
| [dual-stack-preferred-svc.yaml](dual-stack-preferred-svc.yaml) | `ipFamilyPolicy: PreferDualStack` |
| [dual-stack-preferred-ipfamilies-svc.yaml](dual-stack-preferred-ipfamilies-svc.yaml) | `PreferDualStack` + `ipFamilies: [IPv6, IPv4]` |

---

## Lab 1 – Is this cluster dual-stack?
```bash
kubectl get pod -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\n' | grep service-cluster-ip-range
#   --service-cluster-ip-range=10.96.0.0/12          <- ONE range = single-stack
kubectl get node minikube -o jsonpath='{.spec.podCIDRs} {.status.addresses}{"\n"}'     # ["10.244.0.0/24"], IPv4 only
kubectl get pods -A -o jsonpath='{range .items[0:3]}{.status.podIPs}{"\n"}{end}'       # one IP each
```

## Lab 2 – The docs' Services on a single-stack cluster
```bash
cd concepts/services-networking/dual-stack
i=0; for f in dual-stack-*.yaml; do i=$((i+1)); kubectl create ns ds-$i >/dev/null; printf '%-42s ' $f
  kubectl apply -f $f -n ds-$i >/dev/null 2>/tmp/err && kubectl get svc my-service -n ds-$i -o jsonpath='{.spec.ipFamilyPolicy} {.spec.ipFamilies} {.spec.clusterIPs}{"\n"}' || cut -c1-110 /tmp/err; done
```
Expected:
```
dual-stack-default-svc.yaml                SingleStack ["IPv4"] ["10.105.122.233"]
dual-stack-preferred-ipfamilies-svc.yaml   The Service "my-service" is invalid: spec.ipFamilies[0]: Invalid value: "IPv6": not configured on this cluster
dual-stack-preferred-svc.yaml              PreferDualStack ["IPv4"] ["10.110.206.216"]     <- "prefer": quietly falls back to one family
```
```bash
kubectl create service clusterip rds -n ds-1 --tcp=80 --dry-run=client -o json | jq '.spec.ipFamilyPolicy="RequireDualStack"' | kubectl apply -f -
#   spec.ipFamilyPolicy: Invalid value: "RequireDualStack": this cluster is not configured for dual-stack services
for j in 1 2 3; do kubectl delete ns ds-$j; done
```
So `PreferDualStack` is safe to ship to any cluster. `RequireDualStack` and explicit `IPv6` fail on single-stack clusters.

## Lab 3 – On a dual-stack cluster (reference)
On a dual-stack cluster (for example kind with `networking.ipFamily: dual`), the same files give:
```
dual-stack-default-svc.yaml              SingleStack     [IPv4]        [10.96.x.x]
dual-stack-preferred-svc.yaml            PreferDualStack [IPv4 IPv6]   [10.96.x.x fd00::x]
dual-stack-preferred-ipfamilies-svc.yaml PreferDualStack [IPv6 IPv4]   [fd00::x 10.96.x.x]   <- IPv6 primary
```
and `kubectl get pod -o jsonpath='{.status.podIPs}'` lists two addresses per pod.

---

## Useful commands
```bash
kubectl get svc -o custom-columns=NAME:.metadata.name,POLICY:.spec.ipFamilyPolicy,FAMILIES:.spec.ipFamilies,IPS:.spec.clusterIPs
kubectl get nodes -o jsonpath='{range .items[*]}{.spec.podCIDRs}{"\n"}{end}'
kubectl explain service.spec.ipFamilyPolicy
```

## Cleanup
```bash
./cleanup.sh
```
