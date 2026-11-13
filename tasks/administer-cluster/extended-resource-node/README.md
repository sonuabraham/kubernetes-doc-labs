# Advertise Extended Resources for a Node – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/extended-resource-node/

> Runs on the default **minikube** node. The docs' PATCH requests are sent verbatim through `kubectl proxy`. [01-dongle-pods.yaml](01-dongle-pods.yaml) is extra: two Pods consume the dongles, which is a preview of the next page, *Assign Extended Resources to a Container*. [cleanup.sh](cleanup.sh) removes everything the lab advertises.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Extended resource** | Any name in a domain you own (`example.com/dongle`) with an integer count. Kubernetes doesn't know what it *is*; it only does the bookkeeping. |
| **Advertise** | JSON-patch on the **`status` subresource**: `/status/capacity/example.com~1dongle` (`~1` is how JSON Pointer writes `/`, RFC 6901). |
| **capacity → allocatable** | You set `capacity`. The kubelet copies it into `allocatable` at its next status update (~10 s). The scheduler uses allocatable. |
| **Integers only** | `4.5` is rejected (stored as `4500m`, which isn't an integer). For divisible things, advertise small units: `800Gi` bytes instead of 8 × 100 GiB. |
| **Consumers** | Pods set it under `limits` (a request, if given, must **equal** the limit). No overcommit. |
| **Removing it** | Doesn't evict Pods that already hold the resource. It only stops new scheduling. |

---

## Step 0
```bash
cd tasks/administer-cluster/extended-resource-node
kubectl get nodes                  # minikube   Ready   control-plane
kubectl proxy &                    # serves on 127.0.0.1:8001
```

## Lab 1 – Advertise four dongles (the docs' PATCH)
```bash
curl --header "Content-Type: application/json-patch+json" \
  --request PATCH \
  --data '[{"op": "add", "path": "/status/capacity/example.com~1dongle", "value": "4"}]' \
  http://localhost:8001/api/v1/nodes/minikube/status
#   "capacity": { "cpu": "8", "ephemeral-storage": "...", "example.com/dongle": "4", ..., "memory": "31826084Ki", "pods": "110" }
#   "allocatable": { ... no dongle yet ... }
sleep 12; kubectl describe node minikube | grep -E "^Capacity|^Allocatable|dongle"
#   Capacity:     example.com/dongle:  4
#   Allocatable:  example.com/dongle:  4        <- copied by the kubelet
#   (Allocated resources)  example.com/dongle  0  0
```
A fraction is refused:
```bash
curl -s --header "Content-Type: application/json-patch+json" --request PATCH \
  --data '[{"op": "add", "path": "/status/capacity/example.com~1halfdongle", "value": "4.5"}]' \
  http://localhost:8001/api/v1/nodes/minikube/status | grep message
#   "message": "Node \"minikube\" is invalid: status.capacity.example.com/halfdongle: Invalid value: \"4500m\": must be an integer"
```

## Lab 2 (extra) – Use them
```bash
kubectl apply -f 01-dongle-pods.yaml
kubectl -n dongle-demo get po
#   dongle-2   0/1   Pending     <- 3 + 2 > 4
#   dongle-3   1/1   Running
kubectl -n dongle-demo get events --field-selector reason=FailedScheduling -o custom-columns=MSG:.message
#   0/1 nodes are available: 1 Insufficient example.com/dongle. preemption: ...
kubectl -n dongle-demo get po dongle-2 -o jsonpath='{.spec.containers[0].resources}{"\n"}'
#   {"limits":{"example.com/dongle":"2"},"requests":{"example.com/dongle":"2"}}      <- request defaulted to the limit
kubectl describe node minikube | grep -A12 "Allocated resources" | grep dongle
#   example.com/dongle  3  3
kubectl -n dongle-demo run req-only --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"x","image":"busybox:1.36","resources":{"requests":{"example.com/dongle":"1"},"limits":{"example.com/dongle":"2"}}}]}}'
#   The Pod "req-only" is invalid: spec.containers[0].resources.requests: Invalid value: "1": must be equal to example.com/dongle limit of 2
```

## Lab 3 – The storage example: advertise bytes
```bash
curl -s --header "Content-Type: application/json-patch+json" --request PATCH \
  --data '[{"op": "add", "path": "/status/capacity/example.com~1special-storage", "value": "800Gi"}]' \
  http://localhost:8001/api/v1/nodes/minikube/status >/dev/null
sleep 12; kubectl describe node minikube | grep special-storage
#   example.com/special-storage:  800Gi        (Capacity and Allocatable)
kubectl -n dongle-demo run store --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"x","image":"busybox:1.36","command":["sleep","3600"],"resources":{"limits":{"example.com/special-storage":"150Gi"}}}]}}'
kubectl -n dongle-demo get po store            # Running - any byte amount up to 800Gi can be requested
```

## Lab 4 – Remove the advertisement (the docs' cleanup)
```bash
curl --header "Content-Type: application/json-patch+json" \
  --request PATCH \
  --data '[{"op": "remove", "path": "/status/capacity/example.com~1dongle"}]' \
  http://localhost:8001/api/v1/nodes/minikube/status
sleep 12; kubectl describe node minikube | grep dongle
#   (only the dongle-demo Pod lines - no example.com/dongle capacity/allocatable left)
kubectl -n dongle-demo get po
#   dongle-3   1/1   Running     <- not evicted
#   dongle-2   0/1   Pending     <- can never schedule now
kill %1
```
(The HTTP sample on the docs page has a trailing comma after `"path": ...` inside the JSON, which is invalid JSON. The curl command is correct.)

---

## Useful commands
```bash
kubectl get node <n> -o jsonpath='{.status.capacity}{"\n"}{.status.allocatable}{"\n"}'
kubectl patch node <n> --subresource=status --type=json -p '[{"op":"add","path":"/status/capacity/example.com~1dongle","value":"4"}]'
```

## Cleanup
```bash
./cleanup.sh          # namespace + dongle/special-storage advertisements
```
