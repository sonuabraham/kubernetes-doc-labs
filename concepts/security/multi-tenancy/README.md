# Multi-tenancy – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/multi-tenancy/

> A design page (no YAML). This lab builds the page's **namespace-per-tenant** model for two tenants with [tenant.sh](tenant.sh) and checks each isolation layer. Every tenant namespace gets PSA labels, a tenant-admin SA (`admin` ClusterRole), a ResourceQuota (including object counts), LimitRange defaults, and NetworkPolicies (default deny + same namespace + DNS).

## Key ideas (read first)

| Layer | Mechanism | Notes |
|---|---|---|
| **Use cases** | Multiple **teams** (trusted-ish, shared cluster) vs multiple **customers** (untrusted, SaaS) | The trust level decides how strong isolation must be |
| **Control plane** | **Namespaces** + **RBAC** + **ResourceQuota** (+ LimitRange) | Cluster-scoped objects (CRDs, ClusterRoles, nodes, PVs) are shared and need special care |
| **Network** | NetworkPolicy (needs an enforcing CNI), service mesh mTLS | Default-deny per namespace |
| **Storage** | Dynamic provisioning per StorageClass, `Delete` reclaim; avoid `hostPath` | |
| **Sandboxing** | gVisor or Kata via RuntimeClass | For untrusted code |
| **Nodes** | Dedicated nodes per tenant (taints/tolerations + node affinity) | Strongest without separate clusters |
| **Shared things** | **API Priority and Fairness**, QoS, **DNS** (one cluster DNS for all), operators | Noisy neighbours, information leaks |
| **Implementations** | **Namespace per tenant** (cheap, soft) → **virtual control plane per tenant** (vcluster etc., stronger) → cluster per tenant | |

---

## Step 1
```bash
cd concepts/security/multi-tenancy
./tenant.sh a ; ./tenant.sh b
for t in a b; do kubectl apply -n tenant-$t -f 01-apps.yaml; done       # web (nginx) + Service + client in each
```

## Lab 1 – Network isolation
```bash
kubectl exec client -n tenant-a -- wget -q -T 3 -O /dev/null http://web.tenant-a.svc.cluster.local && echo OK   # OK
kubectl exec client -n tenant-a -- wget -q -T 3 -O /dev/null http://web.tenant-b.svc.cluster.local              # download timed out = BLOCKED
kubectl exec client -n tenant-a -- wget -q -T 3 -O /dev/null http://example.com                                  # BLOCKED (egress)
kubectl get pods -n kube-system -l app=kindnet -o jsonpath='{.items[0].spec.containers[0].image}'     # kindest/kindnetd:v20260820-…
```
**minikube's kindnet enforces NetworkPolicy** (current kindnetd versions do). Older setups needed Calico or Cilium. Delete tenant b's policies and a→b is **still** blocked: tenant a's own *egress* policy blocks it. Isolation holds if either side denies.

## Lab 2 – DNS is shared
```bash
kubectl exec client -n tenant-a -- nslookup web.tenant-b.svc.cluster.local
#   Address: 10.105.71.233            <- tenant a can enumerate tenant b's Service names/IPs
```
NetworkPolicy blocks traffic, not discovery. Hiding names needs DNS policy (e.g. a CoreDNS plugin) or separate clusters.

## Lab 3 – Control-plane isolation (as tenant a's admin)
```bash
AA="--as=system:serviceaccount:tenant-a:a-admin"
kubectl get pods -n tenant-a $AA                  # OK
kubectl get pods -n tenant-b $AA                  # Forbidden
kubectl get ns $AA                                # Forbidden: namespaces are cluster-scoped
kubectl delete resourcequota tenant-quota -n tenant-a $AA      # Forbidden - admin can't lift its own quota
kubectl create rolebinding grab -n tenant-a $AA --clusterrole=cluster-admin --serviceaccount=tenant-a:a-admin
#   Forbidden (RBAC escalation check - see ../rbac-good-practices)
kubectl delete netpol default-deny -n tenant-a $AA
#   networkpolicy "default-deny" deleted      <- !!
```
**The built-in `admin` ClusterRole may edit NetworkPolicies**, so a tenant can remove its own isolation. For hostile tenants, give them a custom role without `networkpolicies` write, or enforce isolation with cluster-level policy the tenant can't edit (AdminNetworkPolicy, or admission policy). Re-run `./tenant.sh a` to restore it.

## Lab 4 – Quotas against noisy neighbours
```bash
kubectl create deploy hog -n tenant-a $AA --image=busybox:1.36 --replicas=15 -- sleep 3600
kubectl get deploy hog -n tenant-a                          # 8/15: stuck at the quota
kubectl get resourcequota tenant-quota -n tenant-a -o jsonpath='{.status.used}'
#   {"limits.cpu":"2","pods":"10",...}                       <- LimitRange gave each Pod 200m limit, so limits.cpu=2 and pods=10 both hit
kubectl get events -n tenant-a --field-selector reason=FailedCreate -o custom-columns=M:.message | tail -1
#   exceeded quota: tenant-quota, requested: limits.cpu=200m,pods=1, used: limits.cpu=2 ...
```

## Lab 5 – Other shared resources
```bash
kubectl get flowschemas -o custom-columns=NAME:.metadata.name,PL:.spec.priorityLevelConfiguration.name
#   service-accounts → workload-low ; global-default → global-default      <- all tenants' SAs share one priority level
kubectl get pod web -n tenant-a -o jsonpath='{.status.qosClass}'        # Burstable (LimitRange defaults)
```
APF keeps one tenant's API storm from starving the control plane. Give tenants their own FlowSchemas and priority levels for fairness *between* tenants.

---

## Useful commands
```bash
kubectl auth can-i --list --as=system:serviceaccount:tenant-a:a-admin -n tenant-a
kubectl describe resourcequota -n <ns> ; kubectl get netpol -A
kubectl get flowschemas,prioritylevelconfigurations
```

## Cleanup
```bash
./cleanup.sh
```
