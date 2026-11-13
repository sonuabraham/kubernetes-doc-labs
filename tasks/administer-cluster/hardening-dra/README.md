# Harden Dynamic Resource Allocation in Your Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/hardening-dra/

> Runs on the default **minikube** cluster (DRA is GA; `DRAResourceClaimGranularStatusAuthorization` is beta and on in 1.37). The docs' three ClusterRoles are applied **verbatim**: [01-dra-binding-updater.yaml](01-dra-binding-updater.yaml), [02-dra-node-driver-status-updater.yaml](02-dra-node-driver-status-updater.yaml), [03-dra-multinode-status-updater.yaml](03-dra-multinode-status-updater.yaml). Extra files:
> - [04-test-setup.yaml](04-test-setup.yaml): a DeviceClass, a ResourceClaim, and one ServiceAccount + binding per component, plus `status-only` with just the pre-1.36 permission.
> - [05-node-driver-pod.yaml](05-node-driver-pod.yaml): a node-local "driver" Pod that uses its own node-bound token.
>
> No real DRA driver is needed: the status updates are made by hand, as each identity, through the API.

## Key ideas (read first)

| What is written | Needs (since v1.36) | Who |
|---|---|---|
| `status.allocation` / `status.reservedFor` | `resourceclaims/status` **and** synthetic `resourceclaims/binding` (`patch`/`update`) | kube-scheduler or a custom allocator |
| `status.devices` (per-device conditions, data, network info) | `resourceclaims/status` **and** synthetic `resourceclaims/driver` with a **node-aware verb**, scoped by `resourceNames: [<driver name>]` | DRA drivers |
| node-aware verbs | `associated-node:patch/update`: the request must come from a ServiceAccount token bound to a Pod **on the node the claim is allocated to**. `arbitrary-node:*`: from anywhere (multi-node controllers only). | |

Bind each role to its own identity, use `resourceNames` so a driver can only write its own devices' status, and audit denied `resourceclaims/binding` / `resourceclaims/driver` requests.

---

## Step 0
```bash
cd tasks/administer-cluster/hardening-dra
kubectl apply -f 01-dra-binding-updater.yaml -f 02-dra-node-driver-status-updater.yaml -f 03-dra-multinode-status-updater.yaml -f 04-test-setup.yaml
as(){ kubectl -n dra-demo patch resourceclaim gpu-claim --subresource=status --type=merge -p "$2" --as=system:serviceaccount:dra-demo:$1; }
ALLOC='{"status":{"allocation":{"devices":{"results":[{"request":"gpu","driver":"dra.example.com","pool":"pool-a","device":"gpu-0"}]}}}}'
DEV='{"status":{"devices":[{"driver":"dra.example.com","pool":"pool-a","device":"gpu-0","conditions":[{"type":"Ready","status":"True","reason":"Configured","message":"ok","lastTransitionTime":"2026-11-14T00:00:00Z"}]}]}}'
```

## Lab 1 – Allocation needs `resourceclaims/binding`
```bash
as status-only "$ALLOC"
#   The ResourceClaim "gpu-claim" is invalid: status.allocation: Forbidden: changing status.allocation or status.reservedFor
#   requires resource="resourceclaims/binding", verb="patch" permission ...      <- resourceclaims/status alone is no longer enough
as multinode-controller "$ALLOC"          # same Forbidden - a driver role can't allocate
as allocator "$ALLOC"                     # dra-binding-updater
#   resourceclaim.resource.k8s.io/gpu-claim patched
```

## Lab 2 – Device status needs `resourceclaims/driver` + a node-aware verb
```bash
as status-only "$DEV"; as allocator "$DEV"; as node-driver "$DEV"
#   status.devices: Forbidden: changing status.devices requires resource="resourceclaims/driver", verb="[arbitrary-node:patch]" permission:
#   resourceclaims.resource.k8s.io "dra.example.com" is forbidden: User "system:serviceaccount:dra-demo:..." ...
as multinode-controller "$DEV"            # dra-multinode-status-updater (arbitrary-node:*)
#   resourceclaim.resource.k8s.io/gpu-claim patched
```
Even `node-driver` is refused here: an impersonated request (`--as`) carries no node, so the API server asks for `arbitrary-node:patch`.

`resourceNames` limits a role to its driver:
```bash
# allocate a device of driver other.example.com (as allocator), then:
kubectl -n dra-demo patch resourceclaim gpu-claim --subresource=status --type=merge \
  -p '{"status":{"devices":[{"driver":"other.example.com","pool":"p","device":"d0"}]}}' --as=system:serviceaccount:dra-demo:multinode-controller
#   ... resourceclaims.resource.k8s.io "other.example.com" is forbidden ...      <- role is scoped to "dra.example.com"
```

## Lab 3 – The node-local driver role, used the way it's meant to be
Re-allocate the claim **to node `minikube`** (as `allocator`, with `nodeSelector` `metadata.name In [minikube]`), then run the "driver" Pod there:
```bash
kubectl -n dra-demo patch resourceclaim gpu-claim --subresource=status --type=json -p '[{"op":"remove","path":"/status/devices"},{"op":"remove","path":"/status/allocation"}]'
kubectl -n dra-demo patch resourceclaim gpu-claim --subresource=status --type=merge --as=system:serviceaccount:dra-demo:allocator \
  -p '{"status":{"allocation":{"nodeSelector":{"nodeSelectorTerms":[{"matchFields":[{"key":"metadata.name","operator":"In","values":["minikube"]}]}]},"devices":{"results":[{"request":"gpu","driver":"dra.example.com","pool":"pool-a","device":"gpu-0"}]}}}}'
kubectl apply -f 05-node-driver-pod.yaml
kubectl -n dra-demo logs node-driver
#   token node claim: "node":{"name":"minikube","uid":"e50a8c8b-..."}          <- projected token says where the Pod runs
#   response message: set by node-local driver                                  <- associated-node:patch was enough
```
The same Pod against a claim allocated to **another** node (`values: ["some-other-node"]`):
```bash
#   response message: Forbidden: changing status.devices requires resource=\"resourceclaims/driver\", verb=\"[arbitrary-node:patch]\" ...
#   User \"system:serviceaccount:dra-demo:node-driver\" cannot arbitrary-node:patch resource \"resourceclaims/driver\" ...
```
A compromised node-local driver therefore can't tamper with claims on other nodes.

---

## Useful commands
```bash
kubectl auth can-i patch resourceclaims/binding -n <ns> --as=system:serviceaccount:<ns>:<sa>
kubectl auth can-i associated-node:patch resourceclaims/driver/dra.example.com -n <ns> --as=...
kubectl get resourceclaim <claim> -o jsonpath='{.status}'
```

## Cleanup
```bash
./cleanup.sh       # test setup (namespace, SAs, bindings, DeviceClass) + the three ClusterRoles
```
