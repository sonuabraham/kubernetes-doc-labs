# Hardening Guide – Dynamic Resource Allocation – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/hardening-guide/dynamic-resource-allocation/

> The docs' 3 ClusterRoles are **verbatim**: [01-dra-binding-updater.yaml](01-dra-binding-updater.yaml), [02-dra-node-driver-status-updater.yaml](02-dra-node-driver-status-updater.yaml), [03-dra-multinode-status-updater.yaml](03-dra-multinode-status-updater.yaml). [00-setup.yaml](00-setup.yaml) adds a DeviceClass, a ResourceClaim and four ServiceAccounts. [try.sh](try.sh) patches the claim's status **as** a ServiceAccount, using its own token. No real DRA driver is needed: we write the status fields ourselves, which is exactly what the authorization guards.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Problem** | `resourceclaims/status` used to be one permission: whoever had it could rewrite allocations **and** device status, for any driver. |
| **DRAResourceClaimGranularStatusAuthorization** (beta, on) | In addition to `resourceclaims/status`, the API server checks **synthetic subresources** based on the fields being changed. |
| **`resourceclaims/binding`** | Needed to change `status.allocation` / `status.reservedFor`. Verbs `update`/`patch`. For the **scheduler** and allocation controllers. |
| **`resourceclaims/driver`** | Needed to change `status.devices`. Checked **per driver** (`resourceNames: [driver name]`) with **node-aware verbs**. |
| **`associated-node:<verb>`** | Node-local drivers. The request must come from an identity tied to the **node** of the claim (a pod-bound SA token carries the node). |
| **`arbitrary-node:<verb>`** | Control-plane or multi-node controllers that may update claims for any node. |

---

## Step 1
```bash
cd concepts/security/hardening-guide/dynamic-resource-allocation
kubectl apply -f 00-setup.yaml -f 01-dra-binding-updater.yaml -f 02-dra-node-driver-status-updater.yaml -f 03-dra-multinode-status-updater.yaml
for p in "status-only dra-status-only" "allocator dra-binding-updater" "node-driver dra-node-driver-status-updater" "multi-driver dra-multinode-status-updater"; do
  set -- $p; kubectl create clusterrolebinding dra-$1 --clusterrole=$2 --serviceaccount=dra-harden:$1; done
```

## Lab 1 – Who may allocate (status.allocation → `resourceclaims/binding`)
```bash
for sa in status-only multi-driver allocator; do echo -n "$sa: "; ./try.sh $sa allocation; done
#   status-only:  cannot patch resource "resourceclaims/binding" ...       <- plain status permission is NOT enough any more
#   multi-driver: cannot patch resource "resourceclaims/binding" ...       <- a driver can't (re)allocate
#   allocator:    resourceclaim.resource.k8s.io/gpu-claim patched         <- docs dra-binding-updater
```

## Lab 2 – Who may report device status (status.devices → `resourceclaims/driver`)
```bash
./try.sh status-only devices      # cannot arbitrary-node:patch resource "resourceclaims/driver"
./try.sh allocator devices        # cannot arbitrary-node:patch ...        <- the scheduler can't fake driver data
./try.sh node-driver devices      # cannot arbitrary-node:patch ...        <- token has no node: falls back to arbitrary-node, which it lacks
./try.sh node-driver devices pod-bound
#   patched                        <- token bound to a Pod on node minikube = associated with the claim's node (associated-node:patch)
./try.sh multi-driver devices     # patched (arbitrary-node verbs, no node needed)
```
The check is per **driver name** too (`resourceNames: ["dra.example.com"]`). Adding a `status.devices` entry for `other.example.com` as multi-driver:
```
User "...:multi-driver" cannot arbitrary-node:patch resource "resourceclaims/driver" ...
status.devices[1]: Invalid value: {"Driver":"other.example.com",...}: must be an allocated device in the claim
```
Both authorization **and** validation reject it.

### Result
| SA (role) | status.allocation | status.devices |
|---|---|---|
| status-only (`resourceclaims/status` only) | ✗ | ✗ |
| allocator (dra-binding-updater) | ✓ | ✗ |
| node-driver (associated-node), plain token | ✗ | ✗ |
| node-driver, **pod-bound token** on the claim's node | ✗ | ✓ |
| multi-driver (arbitrary-node) | ✗ | ✓ |

---

## Useful commands
```bash
kubectl auth can-i patch resourceclaims --subresource=binding --as=system:serviceaccount:<ns>:<sa>
kubectl get resourceclaim <c> -o jsonpath='{.status}'
kubectl get clusterroles -o json | jq -r '.items[] | select(any(.rules[]?; .resources|index("resourceclaims/driver","resourceclaims/binding"))) | .metadata.name'
```

## Cleanup
```bash
./cleanup.sh
```
