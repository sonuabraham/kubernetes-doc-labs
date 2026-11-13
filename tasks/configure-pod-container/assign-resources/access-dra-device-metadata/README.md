# Access DRA Device Metadata – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-resources/access-dra-device-metadata/

> Runs on **`dra-lab`**. The docs' examples request `deviceClassName: gpu.example.com`, the class of the upstream dra-example-driver. Here a second instance of the lab driver runs under that driver name (2 GPUs), with that DeviceClass. Files:
> - [dra-device-metadata-pod.yaml](dra-device-metadata-pod.yaml), [dra-device-metadata-template-pod.yaml](dra-device-metadata-template-pod.yaml): the docs' manifests, **verbatim**.
> - [deviceclass-gpu-example-com.yaml](deviceclass-gpu-example-com.yaml): **not from the docs**, the DeviceClass the examples assume.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Device metadata** | Beta in 1.37. A driver that enables it (kubeletplugin option `EnableDeviceMetadata`) has the kubelet framework mount a read-only JSON file per request into each container that uses the claim, so the workload learns *which* device it got (attributes such as model and UUID) without calling the API server. |
| **Path** | `/var/run/kubernetes.io/dra-device-attributes/resourceclaims/<claimName>/<request>/<driver>-metadata.json` for a ResourceClaim. `.../resourceclaimtemplates/<podClaimName>/<request>/<driver>-metadata.json` for a template, where the path uses the Pod's claim *entry* name because the generated claim name is random. |
| **Format** | `kind: DeviceMetadata`, `apiVersion: metadata.resource.k8s.io/v1beta1`, the claim's `metadata`, `podClaimName` (template case), and `requests[].devices[]` with `driver`, `pool`, `name`, `attributes`. |
| **Who decides** | The **driver** opts in and chooses the attributes. Your Pod needs nothing special. |

---

## Step 0 – A driver named `gpu.example.com` and its class
```bash
cd tasks/configure-pod-container/assign-resources
./driver.sh start gpu.example.com 2
$K get resourceslices
#   00000-driver.example.com-dra-lab-r9bhr   dra-lab   driver.example.com   dra-lab
#   00000-gpu.example.com-dra-lab-4jw84      dra-lab   gpu.example.com      dra-lab
cd access-dra-device-metadata
$K apply -f deviceclass-gpu-example-com.yaml
```

## Lab 1 – Metadata of a ResourceClaim (the docs' example)
```bash
$K apply -f dra-device-metadata-pod.yaml
$K wait --for=condition=Ready pod/gpu-metadata-reader
$K logs gpu-metadata-reader
#   === DRA device metadata ===
#   /var/run/kubernetes.io/dra-device-attributes/resourceclaims/gpu-claim/gpu/gpu.example.com-metadata.json
#   {"kind":"DeviceMetadata","apiVersion":"metadata.resource.k8s.io/v1beta1",
#    "metadata":{"name":"gpu-claim","namespace":"default","uid":"...","generation":1},
#    "requests":[{"name":"gpu","devices":[{"driver":"gpu.example.com","pool":"dra-lab","name":"gpu-0",
#      "attributes":{"model":{"string":"lab-gpu-64g"},"type":{"string":"gpu"},"uuid":{"string":"GPU-dra-lab-gpu-0"}}}]}]}
$K exec gpu-metadata-reader -- cat /var/run/kubernetes.io/dra-device-attributes/resourceclaims/gpu-claim/gpu/gpu.example.com-metadata.json
#   (same JSON)
```
The attributes are the ones the driver returned from Prepare (`type`, `model`, `uuid`), not a copy of the ResourceSlice.

## Lab 2 – Metadata with a ResourceClaimTemplate (the docs' example)
```bash
$K apply -f dra-device-metadata-template-pod.yaml
$K wait --for=condition=Ready pod/gpu-metadata-template-reader
$K exec gpu-metadata-template-reader -- cat /var/run/kubernetes.io/dra-device-attributes/resourceclaimtemplates/my-gpu/gpu/gpu.example.com-metadata.json | jq -c '{claim: .metadata.name, podClaimName, devices: [.requests[].devices[].name]}'
#   {"claim":"gpu-metadata-template-reader-my-gpu-52z79","podClaimName":"my-gpu","devices":["gpu-1"]}
$K exec gpu-metadata-template-reader -- sh -c 'mount | grep dra-device-attributes'
#   ... on /run/kubernetes.io/dra-device-attributes/resourceclaimtemplates/my-gpu/gpu/gpu.example.com-metadata.json type ext4 (ro,...)
```
The path uses `my-gpu`, the Pod's `resourceClaims[].name`. The real generated claim name and `podClaimName` are inside the file. The file is a read-only bind mount.

---

## Useful commands
```bash
kubectl exec <pod> -- find /var/run/kubernetes.io/dra-device-attributes -name '*-metadata.json'
kubectl get resourceclaim <name> -o jsonpath='{.status.devices}'      # per-device status the driver may also publish
```

## Cleanup
```bash
$K delete -f dra-device-metadata-pod.yaml -f dra-device-metadata-template-pod.yaml
$K delete -f deviceclass-gpu-example-com.yaml -f ../set-up-dra-cluster/deviceclass.yaml
../driver.sh stop gpu.example.com; ../driver.sh stop driver.example.com
minikube delete -p dra-lab
```
