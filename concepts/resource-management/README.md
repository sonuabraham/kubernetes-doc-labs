# Resource Management – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/resource-management/

| Page | Environment | Lab shows |
|---|---|---|
| [resource-managers](resource-managers/) | `rm-lab` profile (kubelet CPU/memory/topology managers) | which containers get exclusive CPUs; NUMA-pinned memory |
| [pod-level-resource-managers](pod-level-resource-managers/) | `rm-lab` + PodLevelResourceManagers | pod bubble with an internal shared pool vs the hybrid container scope |
| [dynamic-resource-allocation](dynamic-resource-allocation/) | fake DRA driver on fake nodes ([fake-dra.sh](dynamic-resource-allocation/fake-dra.sh)) | claims, templates, sharing, exhaustion |
| ↳ [dra-api](dynamic-resource-allocation/dra-api/) | | prioritized list, adminAccess, extended-resource mapping, alpha attributes |
| ↳ [how-dra-works](dynamic-resource-allocation/how-dra-works/) | | claim lifecycle, pre-scheduled Pods, binding conditions (you play the driver) |
| ↳ [dra-observability](dynamic-resource-allocation/dra-observability/) | | device status in claims, kubelet metrics, pool status (alpha) |
| ↳ [dra-features](dynamic-resource-allocation/dra-features/) | | partitionable devices, consumable capacity (shareID, rounding), alpha fields dropped |
| ↳ [device-taints](dynamic-resource-allocation/device-taints/) | | driver taints, DeviceTaintRule eviction, effect None preview |

Related: requests/limits are in `../configuration/manage-resources-containers`, and DRA hardening in `../security/hardening-guide/dynamic-resource-allocation`.
