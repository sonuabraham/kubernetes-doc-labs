# Assign Devices to Pods and Containers – shared lab tooling

The three DRA pages ([set-up-dra-cluster](set-up-dra-cluster/), [allocate-devices-dra](allocate-devices-dra/), [access-dra-device-metadata](access-dra-device-metadata/)) each assume that a vendor **DRA driver** is installed. They don't install one. minikube has no GPUs, so this folder contains a small but **real** DRA driver (not from the docs):

| File | What |
|---|---|
| [lab-dra-driver/main.go](lab-dra-driver/main.go) | A kubelet DRA plugin built with `k8s.io/dynamic-resource-allocation/kubeletplugin` v0.37. It registers with the kubelet, publishes a **ResourceSlice** with N fake GPUs (`gpu-0..`, attributes `type=gpu`, `model`, `uuid`, `index`, `driverVersion`, capacity `memory: 64Gi`), and on **Prepare** writes a **CDI** spec into `/var/run/cdi`. That spec injects `GPU_DEVICE_<n>=gpu-x`, `..._REQUEST` and `..._CLAIM` env vars into the containers using the claim, so a container really "receives" its device. **Unprepare** deletes the spec. It enables **device metadata** (`metadata.resource.k8s.io/v1beta1`). |
| [driver.sh](driver.sh) | `./driver.sh start <driver-name> [gpus]`, `stop` or `logs`. Copies the binary to the node and runs it as the systemd unit `lab-dra-<name>` (it uses the node's admin.conf; a real driver runs as a DaemonSet with its own ServiceAccount). Several instances with different driver names can run at once. Profile: `P=dra-lab`. |

Build it (Go 1.26 is needed by the v0.37 libraries; `GOTOOLCHAIN=auto` fetches it). The binary is gitignored:
```bash
cd tasks/configure-pod-container/assign-resources/lab-dra-driver
docker run --rm -e GOTOOLCHAIN=auto -v $PWD:/src -w /src golang:1.25 sh -c \
  'go mod tidy && CGO_ENABLED=0 go build -o lab-dra-driver . && chown -R 1000:1000 /src'
```

Cluster used by all three labs (k8s v1.37, containerd 2.3 with `enable_cdi = true`, `cdi_spec_dirs = ['/etc/cdi', '/var/run/cdi']`):
```bash
minikube start -p dra-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0
kubectl config use-context minikube; K="kubectl --context dra-lab"
```
Cleanup after the three labs: `minikube delete -p dra-lab`.
