# Local Ephemeral Storage – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/storage/ephemeral-storage/

> The docs' `frontend` Pod is **verbatim** in [01-frontend.yaml](01-frontend.yaml). Its images (`images.my-company.example/…`) are placeholders, so [02-frontend-runnable.yaml](02-frontend-runnable.yaml) is the same Pod with busybox and a writer that overfills the volume.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Local ephemeral storage** | Node-local disk used by Pods for scratch data: **emptyDir** (non-tmpfs), container **writable layers**, and container **logs**. Lost if the node fails. |
| **Node layouts** | One filesystem (kubelet root `/var/lib/kubelet` + logs) or two (a separate runtime filesystem for images and writable layers). The kubelet only tracks filesystems it knows about. |
| **tmpfs emptyDir** | `medium: Memory` counts as **memory**, not ephemeral storage. |
| **Resource** | `ephemeral-storage` in requests/limits (`2Gi`, `500Mi`…). A Pod's request = sum of its containers. |
| **Scheduling** | Requests must fit `node.status.allocatable.ephemeral-storage` minus other Pods' requests. |
| **Enforcement = eviction** | The kubelet measures periodically: emptyDir above its `sizeLimit` → evict the Pod. Sum of container usage (layers + logs + emptyDir) above the sum of limits → evict the Pod. Not a hard I/O stop. |
| **Measurement** | Periodic directory scans (default), or filesystem **project quotas** (`LocalStorageCapacityIsolationFSQuotaMonitoring`, beta, off by default). Those *monitor* faster and see deleted-but-open files, but don't enforce. |
| **ResourceQuota** | `requests.ephemeral-storage` / `limits.ephemeral-storage`. **Only enforced for Pods that declare the resource.** |

---

## Step 1
```bash
cd concepts/storage/ephemeral-storage
kubectl create namespace es-demo
kubectl get node minikube -o jsonpath='capacity={.status.capacity.ephemeral-storage} allocatable={.status.allocatable.ephemeral-storage}{"\n"}'
#   capacity=256891535360 allocatable=256891535360        (~239Gi: the host disk under minikube's docker container)
kubectl apply -n es-demo -f 01-frontend.yaml -f 02-frontend-runnable.yaml -f 03-container-limit.yaml -f 04-too-big-request.yaml
```

## Lab 1 – The docs Pod: scheduled on its requests
```bash
kubectl get pod frontend -n es-demo -o wide          # ImagePullBackOff  minikube  <- placeholder images, but SCHEDULED
kubectl describe node minikube | grep -A8 'Allocated resources' | grep ephemeral
#   ephemeral-storage  4Gi (1%)    8Gi (3%)            <- frontend-runnable's 2×2Gi requests / 2×4Gi limits
```
`frontend` and `frontend-runnable` each request 4Gi. By the time you check, `frontend-runnable` has been evicted (Lab 2) and its requests released.

## Lab 2 – emptyDir sizeLimit → eviction
```bash
kubectl get pod frontend-runnable -n es-demo -o jsonpath='{.status.phase} {.status.reason}: {.status.message}{"\n"}'
#   Failed Evicted: Usage of EmptyDir volume "ephemeral" exceeds the limit "500Mi".
```
The `app` container wrote 600Mi into `/tmp` (the shared emptyDir). The write **succeeded**, and the kubelet's next measurement evicted the whole Pod. Note the 4Gi container limits didn't matter: the volume's own `sizeLimit` tripped first.

## Lab 3 – Container limit → eviction
```bash
kubectl get pod layer-hog -n es-demo -o jsonpath='{.status.phase} {.status.reason}: {.status.message}{"\n"}'
#   Failed Evicted: Pod ephemeral local storage usage exceeds the total limit of containers 100Mi.
```
150Mi written to the container's **writable layer** (`/var/hog`, no volume) against a 100Mi limit.

## Lab 4 – Scheduling on requests
```bash
kubectl get events -n es-demo --field-selector involvedObject.name=wants-a-lot -o custom-columns=M:.message | tail -1
#   0/1 nodes are available: 1 Insufficient ephemeral-storage.
```

## Lab 5 – ResourceQuota
```bash
kubectl create namespace es-quota ; kubectl apply -n es-quota -f 05-quota.yaml     # requests 1Gi, limits 2Gi
kubectl run no-request -n es-quota --image=busybox:1.36 -- sleep 3600             # ADMITTED - nothing declared, nothing counted
kubectl run small -n es-quota --image=busybox:1.36 --overrides='{"spec":{"containers":[{"name":"small","image":"busybox:1.36","command":["sleep","3600"],"resources":{"requests":{"ephemeral-storage":"512Mi"},"limits":{"ephemeral-storage":"1Gi"}}}]}}'
kubectl run small2 -n es-quota --image=busybox:1.36 --overrides='{"spec":{"containers":[{"name":"small2","image":"busybox:1.36","command":["sleep","3600"],"resources":{"requests":{"ephemeral-storage":"768Mi"},"limits":{"ephemeral-storage":"1Gi"}}}]}}'
#   Error from server (Forbidden): pods "small2" is forbidden: exceeded quota: ephemeral-quota, requested: requests.ephemeral-storage=768Mi,
#   used: requests.ephemeral-storage=512Mi, limited: requests.ephemeral-storage=1Gi
```
That's the docs' note in action: the quota only bites Pods that declare `ephemeral-storage`. Compare a CPU quota, which **rejects** Pods without a request:
```bash
kubectl create quota cpu-q -n es-quota --hard=requests.cpu=1
kubectl run no-cpu -n es-quota --image=busybox:1.36 -- sleep 3600
#   Error from server (Forbidden): pods "no-cpu" is forbidden: failed quota: cpu-q: must specify requests.cpu for: no-cpu
```
Use a LimitRange with a default `ephemeral-storage` so every Pod is counted (see `../../policy/limit-range`).

---

## Useful commands
```bash
kubectl get node <n> -o jsonpath='{.status.allocatable.ephemeral-storage}'
kubectl describe node <n> | grep -A8 'Allocated resources'
kubectl get --raw /api/v1/nodes/<n>/proxy/stats/summary | jq '.pods[] | {name: .podRef.name, eph: ."ephemeral-storage".usedBytes}'
kubectl get pods --field-selector status.phase=Failed -o custom-columns=NAME:.metadata.name,REASON:.status.reason,MSG:.status.message
```

## Cleanup
```bash
./cleanup.sh
```
