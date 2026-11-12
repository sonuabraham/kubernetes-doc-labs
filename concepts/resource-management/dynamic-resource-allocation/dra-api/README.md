# DRA – API Objects – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/dra-api/

> The docs' 8 blocks are **verbatim** (descriptive names; `*-excerpt.yaml` contain `...`). The "cat" examples use driver `resource-driver.example.com`. [00-cat-driver.yaml](00-cat-driver.yaml) adds its DeviceClass and a second slice with two small white cats. [deviceclass-extended-resource.yaml](deviceclass-extended-resource.yaml) targets the lab's fake `gpu.example.com` driver (`../fake-dra.sh up`).

## Key ideas (read first)

| Object / field | Meaning |
|---|---|
| **DeviceClass** | Admin-defined category: CEL `selectors` + optional `config`; `extendedResourceName` lets Pods ask with plain `resources.requests` (DRAExtendedResource). |
| **ResourceClaim / Template** | Requests: `exactly` (one way) or `firstAvailable` (a **prioritized list** of alternatives); `count`, `allocationMode: All`, selectors, constraints (`matchAttribute`). |
| **Workload ResourceClaims** | Claims on a **PodGroup**, shared by its Pods (DRAWorkloadResourceClaims, beta, off here; see `../../../workloads/workload-api`). |
| **ResourceSlice** | Driver-published devices: per `nodeName`, `nodeSelector` or `allNodes`, in **pools** (generation, slice count). Attributes are typed (`string`, `int`, `bool`, `version`). |
| **adminAccess** | Monitoring/maintenance access to devices **already in use**. Only in namespaces labelled `resource.kubernetes.io/admin-access: "true"`. |
| **List-type attributes** (alpha) | `strings`/`ints`… values. **Derived attributes** (alpha): computed in the claim for constraints. |

---

## Step 1
```bash
cd concepts/resource-management/dynamic-resource-allocation/dra-api
../fake-dra.sh up
kubectl apply -f 00-cat-driver.yaml -f cat-slice.yaml          # namespace dra-api, 1 large black cat + 2 small white cats (allNodes)
```

## Lab 1 – Prioritized list (docs template)
```bash
kubectl apply -n dra-api -f prioritized-list-claim-template.yaml
for i in 1 2 3; do ./pod.sh cat-$i prioritized-list-claim-template fake-1; done
kubectl get resourceclaims -n dra-api -o custom-columns=CLAIM:.metadata.name,RESULTS:.status.allocation.devices.results[*].request,DEVICES:.status.allocation.devices.results[*].device
#   cat-1-r-…   req-0/large-black                     large-black-cat                       <- first choice
#   cat-2-r-…   req-0/small-white,req-0/small-white   small-white-cat-1,small-white-cat-2   <- fallback: count 2
#   cat-3-r-…   <none>                                                                      <- "cannot allocate all claims"
```
The result names the sub-request that won (`req-0/small-white`), so the workload can see which alternative it got.

## Lab 2 – adminAccess (docs template)
```bash
kubectl apply -n dra-api -f admin-access-claim-template.yaml
#   spec.devices.requests[0].adminAccess: Forbidden: admin access to devices requires the `resource.kubernetes.io/admin-access: true` label on the namespace
kubectl create ns dra-admin ; kubectl label ns dra-admin resource.kubernetes.io/admin-access=true
kubectl apply -n dra-admin -f admin-access-claim-template.yaml
NS=dra-admin ./pod.sh monitor large-black-cat-claim-template fake-1
kubectl get resourceclaims -n dra-admin -o custom-columns=DEVICES:.status.allocation.devices.results[*].device,ADMIN:.status.allocation.devices.results[*].adminAccess
#   large-black-cat,small-white-cat-1,small-white-cat-2   true,true,true     <- ALL devices, though they're allocated to cat-1/cat-2
```

## Lab 3 – Alpha attribute features (off)
```bash
kubectl apply -f list-type-attributes-slice.yaml --dry-run=server
#   spec.devices[0].attributes: Invalid value: "supported-models": a valid C identifier must start with alphabetic character or '_' ...
#   spec.devices[0].attributes[dra.example.com/supported-models]: Invalid value: "": must specify one of: `int`, `bool`, `string`, `version`, `ints`, ...
kubectl apply -n dra-api -f derived-attributes-claim.yaml --dry-run=server -o jsonpath='{.spec.devices.requests[0].exactly}'
#   {"allocationMode":"ExactCount","count":1,"deviceClassName":"gpu.example.com"}        <- derivedAttributes silently dropped
```
The docs' list-type example fails twice: the gate is off (`strings` unknown), **and** the attribute name `supported-models` (with a hyphen) isn't a valid C identifier, so it would need `supported_models`.

## Lab 4 – Extended resources backed by DRA (docs DeviceClass)
```bash
kubectl apply -f deviceclass-extended-resource.yaml        # gpu.example.com with type == 'gpu' and extendedResourceName example.com/gpu
kubectl get node fake-1 -o jsonpath='{.status.allocatable.example\.com/gpu}'            # (empty) - no node advertises it
kubectl run ext -n dra-api --image=registry.k8s.io/pause:3.8 --overrides='{"spec":{"containers":[{"name":"c","image":"registry.k8s.io/pause:3.8","resources":{"requests":{"example.com/gpu":"1"},"limits":{"example.com/gpu":"1"}}}]}}'
kubectl get pod ext -n dra-api -o jsonpath='{.spec.nodeName} {.status.extendedResourceClaimStatus}'
#   fake-2 {"requestMappings":[{"containerName":"c","requestName":"container-0-request-0","resourceName":"example.com/gpu"}],"resourceClaimName":"ext-extended-resources-qggqx"}
```
A classic `resources.requests` was satisfied by a **DRA device** (gpu-0 on fake-2) through an auto-created ResourceClaim. That's the migration path from device plugins.

---

## Useful commands
```bash
kubectl explain resourceclaim.spec.devices.requests --recursive | less
kubectl get resourceslices -o custom-columns=NAME:.metadata.name,DRIVER:.spec.driver,NODE:.spec.nodeName,ALL:.spec.allNodes,DEVICES:.spec.devices[*].name
```

## Cleanup
```bash
./cleanup.sh        # namespaces, cat slices and class; restores the fake gpu.example.com class
```
