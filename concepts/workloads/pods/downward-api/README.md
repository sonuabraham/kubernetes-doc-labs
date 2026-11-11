# Downward API – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/downward-api/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Downward API** | Lets a container learn about itself (name, labels, IP, limits…) **without** talking to the API server, as **env vars** or as **files in a `downwardAPI` volume**. |
| **`fieldRef`** | Pod-level fields. |
| **`resourceFieldRef`** | Container requests and limits (`cpu`, `memory`, `ephemeral-storage`, `hugepages-*`), with an optional `divisor` (`1m`, `1Mi`…). |
| **Env and volume** | `metadata.name`, `metadata.namespace`, `metadata.uid`, `metadata.labels['<k>']`, `metadata.annotations['<k>']` |
| **Env only** | `spec.serviceAccountName`, `spec.nodeName`, `status.hostIP(s)`, `status.podIP(s)` |
| **Volume only** | `metadata.labels` and `metadata.annotations` (all of them, `key="value"` per line) |
| **Updates** | Env vars are fixed at container start. **Volume files are updated** (labels, annotations, and resources after an in-place resize). |
| **No limit set?** | `limits.cpu/memory` fall back to the **node's allocatable** values. |

## The demo app
[00-downward.yaml](00-downward.yaml) is pod `info` (namespace `downward-demo`) exposing **every** field listed on the page: env vars for `main`, plus a `downwardAPI` volume at `/etc/podinfo`. Container `nolimits` has no resources at all. [01-env-only-field-in-volume.yaml](01-env-only-field-in-volume.yaml) tries an env-only field in a volume.

---

## Lab 1 – Everything as env vars
```bash
cd concepts/workloads/pods/downward-api
kubectl apply -f 00-downward.yaml ; kubectl wait --for=condition=Ready pod/info -n downward-demo
kubectl exec info -c main -n downward-demo -- sh -c 'env | sort | grep -E "^(POD_|LABEL_|ANNOT_|SA_|NODE_|HOST_|CPU_|MEM_|SIDECAR_)"'
```
Expected:
```
ANNOT_BUILD=42            LABEL_TIER=backend         <- single label/annotation by key
POD_NAME=info  POD_NAMESPACE=downward-demo  POD_UID=a69a76dd-…
SA_NAME=default  NODE_NAME=minikube  HOST_IP=192.168.58.2  POD_IP=10.244.0.200    <- env-only fields
CPU_REQUEST=100  CPU_LIMIT=200  MEM_LIMIT=64             <- with divisor 1m / 1Mi
SIDECAR_CPU_LIMIT=8                                       <- "nolimits" has no limit -> node allocatable CPU
```

## Lab 2 – Everything as files
```bash
kubectl exec info -c main -n downward-demo -- sh -c 'for f in labels name cpu_limit nolimits_mem_limit; do echo "--- $f"; cat /etc/podinfo/$f; echo; done'
#   --- labels              app="info"  tier="backend"     <- ALL labels, volume-only
#   --- name                info
#   --- cpu_limit           200
#   --- nolimits_mem_limit  31081                          <- node allocatable memory in Mi (no limit set)
kubectl exec info -c main -n downward-demo -- grep -E '^(build|owner)' /etc/podinfo/annotations
kubectl get node minikube -o jsonpath='{.status.allocatable}{"\n"}'     # cpu 8, memory 31826084Ki (= 31081Mi)
```

## Lab 3 – Env is frozen, files follow changes
```bash
kubectl label pod info -n downward-demo tier=frontend --overwrite
kubectl annotate pod info -n downward-demo build=43 --overwrite
kubectl patch pod info -n downward-demo --subresource resize -p '{"spec":{"containers":[{"name":"main","resources":{"limits":{"cpu":"300m"}}}]}}'
sleep 70        # the kubelet refreshes volume contents on its sync period
kubectl exec info -c main -n downward-demo -- sh -c '
  echo "env : LABEL_TIER=$LABEL_TIER ANNOT_BUILD=$ANNOT_BUILD CPU_LIMIT=$CPU_LIMIT"
  echo "file: $(grep tier /etc/podinfo/labels) $(grep ^build /etc/podinfo/annotations) cpu_limit=$(cat /etc/podinfo/cpu_limit)"'
#   env : LABEL_TIER=backend ANNOT_BUILD=42 CPU_LIMIT=200          <- unchanged until the container restarts
#   file: tier="frontend" build="43" cpu_limit=300                 <- updated in place
kubectl exec info -c main -n downward-demo -- ls -la /etc/podinfo   # ..data -> ..<timestamp>  (atomic symlink swap on update)
```

## Lab 4 – Env-only fields can't go into a volume
```bash
kubectl apply -f 01-env-only-field-in-volume.yaml
#   spec.volumes[0].downwardAPI.fieldRef.fieldPath: Unsupported value: "spec.nodeName":
#   supported values: "metadata.annotations", "metadata.labels", "metadata.name", "metadata.namespace", "metadata.uid"
```

---

## Useful commands
```bash
kubectl explain pod.spec.containers.env.valueFrom.fieldRef
kubectl explain pod.spec.volumes.downwardAPI.items
kubectl exec <pod> -- ls -la /etc/podinfo
```

## Cleanup
```bash
./cleanup.sh
```
