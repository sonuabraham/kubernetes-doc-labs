# Set Up DRA in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/assign-resources/set-up-dra-cluster/

> Runs on the throwaway profile **`dra-lab`** (see [../README.md](../README.md)). The page says "install device drivers" but names none, so this lab uses the lab's own driver [../lab-dra-driver](../lab-dra-driver/) as `driver.example.com`. [deviceclass.yaml](deviceclass.yaml) is the docs' DeviceClass, **verbatim**.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **DRA** | Dynamic Resource Allocation: Pods ask for devices with **ResourceClaims**, the scheduler picks matching devices from **ResourceSlices**, and the driver's kubelet plugin prepares them on the node. GA (`resource.k8s.io/v1`) since 1.34, so it's on by default: no feature gates or runtime-config needed in 1.37. |
| **Driver** | A vendor component with two jobs: publish ResourceSlices (inventory) and serve the kubelet's DRA gRPC API (Prepare/Unprepare), registered via `/var/lib/kubelet/plugins_registry/`. |
| **ResourceSlice** | Per node and pool, the list of devices with attributes and capacities. Written by the driver, *never* by you. |
| **DeviceClass** | Written by admins (or by the driver's install). A named set of devices (CEL selectors) plus optional config, referenced by claims. |
| **CDI** | Container Device Interface: the driver tells the runtime (containerd `enable_cdi`) what to inject into containers (device nodes, mounts, env). |

---

## Step 0 – Cluster and driver
```bash
minikube start -p dra-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0
kubectl config use-context minikube; K="kubectl --context dra-lab"
$K get --raw /apis/resource.k8s.io | jq -c '[.versions[].version]'          # ["v1"]
```

## Lab 1 – Verify the DRA API (the docs' check)
```bash
$K get deviceclasses
#   No resources found                 <- the API works and nothing is installed yet
```

## Lab 2 – Install a driver
```bash
cd tasks/configure-pod-container/assign-resources
./driver.sh start driver.example.com 4
#   active
#   driver.example.com-reg.sock             <- registered with the kubelet
```

## Lab 3 – Verify the driver's ResourceSlices (the docs' check)
```bash
$K get resourceslices
#   NAME                                     NODE      DRIVER               POOL      AGE
#   00000-driver.example.com-dra-lab-r9bhr   dra-lab   driver.example.com   dra-lab   8s
$K get resourceslice -o yaml | yq '.items[0].spec'
#   driver: driver.example.com
#   nodeName: dra-lab
#   pool: {generation: 1, name: dra-lab, resourceSliceCount: 1}
#   devices:
#   - name: gpu-0
#     attributes: {driverVersion: {version: 1.0.0}, index: {int: 0}, model: {string: lab-gpu-64g}, type: {string: gpu}, uuid: {string: GPU-dra-lab-gpu-0}}
#     capacity: {memory: {value: 64Gi}}
#   - name: gpu-1 ...
```

## Lab 4 – Create a DeviceClass (the docs' manifest)
```bash
cd set-up-dra-cluster
$K apply -f deviceclass.yaml
#   deviceclass.resource.k8s.io/example-device-class created
$K get deviceclasses
#   NAME                   AGE
#   example-device-class   2s
```
The next page, [../allocate-devices-dra](../allocate-devices-dra/), uses this class and driver.

---

## Useful commands
```bash
kubectl get deviceclasses,resourceslices,resourceclaims,resourceclaimtemplates -A
kubectl get resourceslices --field-selector spec.nodeName=<node>
ls /var/lib/kubelet/plugins_registry/                  # on a node: registered plugins
```

## Cleanup (the docs' command)
```bash
$K delete -f deviceclass.yaml
```
Keep the cluster and driver if you go on to the next page.
