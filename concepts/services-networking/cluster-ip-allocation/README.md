# Service ClusterIP Allocation – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/cluster-ip-allocation/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Dynamic** | No `clusterIP` given → the API server picks a free IP from the service CIDR (`--service-cluster-ip-range`, here `10.96.0.0/12`). |
| **Static** | You set `spec.clusterIP`. Used for well-known addresses, such as DNS at `10.96.0.10`. |
| **Collision risk** | A dynamic allocation could grab "your" static IP first. |
| **Two bands** | The range is split: a **lower static band** of `min(max(16, size/16), 256)` IPs, which dynamic allocation **avoids** while the upper band has room, and an upper dynamic band. Pick static IPs from the **lower** band. |
| **IPAddress objects** | Every allocated ClusterIP is an `IPAddress` object (`networking.k8s.io/v1`) pointing to its Service. |
| **ServiceCIDR objects** | The ranges themselves (`kubectl get servicecidrs`). You can **add** ranges at runtime. A ServiceCIDR in use is protected by a finalizer. |

For `10.96.0.0/12` (1,048,576 IPs): static band = `min(max(16, 65536), 256)` = **256** → `10.96.0.0`–`10.96.0.255`.

## The demo app
[kube-dns-service.yaml](kube-dns-service.yaml) is the docs manifest **verbatim**: the cluster DNS Service with its static `clusterIP: 10.96.0.10`, as it exists in `kube-system`.

---

## Lab 1 – The docs' example is your live kube-dns
```bash
cd concepts/services-networking/cluster-ip-allocation
kubectl diff -f kube-dns-service.yaml ; echo "exit=$?"     # exit=0 - live object matches the docs manifest
kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}{"\n"}'      # 10.96.0.10 - static, from the lower band
```

## Lab 2 – Dynamic IPs avoid the static band
```bash
kubectl create namespace cip-demo
for i in $(seq 1 8); do kubectl create svc clusterip s$i -n cip-demo --tcp=80; done
kubectl get svc -n cip-demo -o custom-columns=NAME:.metadata.name,IP:.spec.clusterIP
#   10.100.242.236  10.97.81.181  10.110.93.183  ...   <- none inside 10.96.0.0-10.96.0.255
```

## Lab 3 – Static IPs and conflicts
```bash
kubectl create svc clusterip static1 -n cip-demo --tcp=80 --clusterip=10.96.0.50        # 10.96.0.50 - granted (lower band)
kubectl create svc clusterip clash -n cip-demo --tcp=80 --clusterip=10.96.0.10
#   failed to allocate IP 10.96.0.10: provided IP is already allocated
kubectl get ipaddress 10.96.0.50 -o jsonpath='{.spec.parentRef}{"\n"}'
#   {"group":"","name":"static1","namespace":"cip-demo","resource":"services"}
kubectl get ipaddresses | head                  # one object per allocated ClusterIP
```

## Lab 4 – Add a Service CIDR at runtime
```bash
kubectl get servicecidrs                         # kubernetes   10.96.0.0/12
kubectl create svc clusterip outside -n cip-demo --tcp=80 --clusterip=10.200.0.5
#   failed to allocate IP 10.200.0.5: the provided network does not match the current range
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: ServiceCIDR
metadata: {name: extra-range}
spec: {cidrs: ["10.200.0.0/24"]}
YAML
kubectl create svc clusterip outside -n cip-demo --tcp=80 --clusterip=10.200.0.5    # 10.200.0.5 - now allowed
kubectl delete servicecidr extra-range --wait=false
kubectl get servicecidr extra-range -o json | jq -c '{finalizers: .metadata.finalizers, cond: .status.conditions}'
#   finalizers ["networking.k8s.io/service-cidr-finalizer"], Ready=False Terminating   <- still used by "outside"
kubectl delete svc outside -n cip-demo ; sleep 5 ; kubectl get servicecidrs     # extra-range gone
```

---

## Useful commands
```bash
kubectl get servicecidrs ; kubectl get ipaddresses
kubectl get svc -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,IP:.spec.clusterIP | sort -t. -k4 -n
```

## Cleanup
```bash
./cleanup.sh
```
