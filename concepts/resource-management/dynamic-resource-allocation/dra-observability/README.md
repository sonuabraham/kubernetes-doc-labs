# DRA Observability – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/resource-management/dynamic-resource-allocation/dra-observability/

> The docs' 4 blocks are **verbatim**: [resourceclaim-device-status-excerpt.yaml](resourceclaim-device-status-excerpt.yaml), [resourcepoolstatusrequest.yaml](resourcepoolstatusrequest.yaml) (indented as in the docs' list), [slice-partition-type-excerpt.yaml](slice-partition-type-excerpt.yaml), [resourcepoolstatusrequest-partitions.yaml](resourcepoolstatusrequest-partitions.yaml). Uses the fake driver (`../fake-dra.sh up`). Where the docs describe what a **driver** writes, you write it yourself.

## Key ideas (read first)

| Signal | Where | Gate |
|---|---|---|
| **kubelet metrics** | `dra_operations_duration_seconds`, `dra_resource_claims_in_use{driver_name}` (+ gRPC metrics) | – |
| **PodResources API** | Node-local gRPC: which claims/devices each container got | KubeletPodResourcesDynamicResources (on) |
| **ResourceClaim device status** | Driver writes `status.devices[]`: conditions, free-form `data`, `networkData` (interface, IPs, MAC) per allocated device | DRAResourceClaimDeviceStatus (on) |
| **Device health** | kubelet puts driver-reported health into `pod.status.containerStatuses[].allocatedResourcesStatus` | ResourceHealthStatus (beta, on) |
| **Resource pool status** | `ResourcePoolStatusRequest` (v1alpha3): ask the API for pool capacity/usage summaries, including partitions and shareable devices | DRAResourcePoolStatus (alpha, **off**) |
| **Device metadata in containers** | Drivers can expose device metadata files to containers (immediate or deferred) | beta in v1.37, driver opt-in |

---

## Lab 1 – Device status written by the "driver"
```bash
cd concepts/resource-management/dynamic-resource-allocation/dra-observability
kubectl create ns dra-obs
# claim nic-claim (gpu.example.com) + Pod "user" → allocated fake-2/gpu-0
kubectl patch resourceclaim nic-claim -n dra-obs --subresource=status --type=merge -p '{"status":{"devices":[{"driver":"gpu.example.com","pool":"fake-2","device":"gpu-0",
  "conditions":[{"type":"Ready","status":"True","reason":"DeviceConfigured","message":"MIG profile applied","lastTransitionTime":"2026-11-12T00:00:00Z"}],
  "data":{"uuid":"GPU-1234","memoryGiB":80},
  "networkData":{"interfaceName":"net1","ips":["10.10.1.2/24"],"hardwareAddress":"00:01:ec:84:fb:51"}}]}}'
kubectl get resourceclaim nic-claim -n dra-obs -o jsonpath='{.status.devices}' | jq -c .
#   [{"conditions":[{...,"reason":"DeviceConfigured","type":"Ready"}],"data":{"memoryGiB":80,"uuid":"GPU-1234"},"device":"gpu-0",
#     "driver":"gpu.example.com","networkData":{"hardwareAddress":"00:01:ec:84:fb:51","interfaceName":"net1","ips":["10.10.1.2/24"]},"pool":"fake-2"}]
kubectl patch resourceclaim nic-claim -n dra-obs --subresource=status --type=merge -p '{"status":{"devices":[{"driver":"gpu.example.com","pool":"nope","device":"gpu-9"}]}}'
#   status.devices[0]: Invalid value: {...,"Pool":"nope","Device":"gpu-9"}: must be an allocated device in the claim
```
The same shape as the docs' macvlan NIC excerpt: tools (CNI, monitoring) read **one** place for "what did this Pod actually get". Who may write it is controlled by the granular status RBAC (`../../../security/hardening-guide/dynamic-resource-allocation`).

## Lab 2 – Resource pool status (alpha, off)
```bash
kubectl apply -f resourcepoolstatusrequest.yaml
#   no matches for kind "ResourcePoolStatusRequest" in version "resource.k8s.io/v1alpha3"      <- API not served
```

## Lab 3 – kubelet metrics (the real minikube node)
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/metrics | grep -E '^# HELP dra_'
#   dra_operations_duration_seconds  [ALPHA] Latency histogram ... handling all ResourceClaims referenced by a pod ...
#   dra_resource_claims_in_use       [ALPHA] The number of ResourceClaims that are currently in use on the node, by driver name
```
They stay at zero here: no real driver prepares anything on minikube. Fake nodes have no kubelet, so device health (`allocatedResourcesStatus`) and in-container device metadata can't be shown.

---

## Useful commands
```bash
kubectl get resourceclaims -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,DEVICES:.status.devices[*].device,READY:.status.devices[*].conditions[0].status
kubectl get pod <p> -o jsonpath='{.status.containerStatuses[*].allocatedResourcesStatus}'
```

## Cleanup
```bash
./cleanup.sh
```
