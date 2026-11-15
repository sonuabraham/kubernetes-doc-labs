# Expose Pod Information to Containers Through Environment Variables – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/

> Runs on the default **minikube** cluster, `default` namespace. Files: [dapi-envars-pod.yaml](dapi-envars-pod.yaml),
> [dapi-envars-container.yaml](dapi-envars-container.yaml) (docs, **verbatim**), [dapi-extras.yaml](dapi-extras.yaml) (not from the docs).
> The same information as files: [downward-api-volume-expose-pod-information](../downward-api-volume-expose-pod-information/).

## Key ideas (read first)

| Source | `valueFrom.…` | Examples |
|---|---|---|
| Pod fields | `fieldRef.fieldPath` | `metadata.name/namespace/uid`, `metadata.labels['k']`, `metadata.annotations['k']`, `spec.nodeName`, `spec.serviceAccountName`, `status.podIP(s)`, `status.hostIP(s)` |
| Container resources | `resourceFieldRef` (+ `containerName`, `divisor`) | `requests.cpu`, `limits.memory`, `requests.ephemeral-storage`… |
| Rounding | values are divided by `divisor` (default `1` = cores / bytes) and **rounded up** | `125m` gives `1` |
| No limit set | `limits.*` gives the **node allocatable** value | |

---

## Lab 1 – Pod fields (docs)
```bash
cd tasks/inject-data-application/environment-variable-expose-pod-information
kubectl apply -f dapi-envars-pod.yaml
kubectl logs dapi-envars-fieldref
#   minikube  dapi-envars-fieldref  default  10.244.0.38  default
kubectl exec dapi-envars-fieldref -- printenv | grep '^MY_' | sort
#   MY_NODE_NAME=minikube
#   MY_POD_IP=10.244.0.38
#   MY_POD_NAME=dapi-envars-fieldref
#   MY_POD_NAMESPACE=default
#   MY_POD_SERVICE_ACCOUNT=default
```

## Lab 2 – Container fields (docs)
```bash
kubectl apply -f dapi-envars-container.yaml
kubectl logs dapi-envars-resourcefieldref
#   1           <- requests.cpu 125m, divisor 1 -> rounded UP to 1
#   1           <- limits.cpu 250m -> 1
#   33554432    <- 32Mi in bytes
#   67108864    <- 64Mi
```

## Lab 3 – Divisors, labels, missing limits (not from the docs)
```bash
kubectl apply -f dapi-extras.yaml
kubectl logs dapi-extras
#   APP_LABEL=dapi-demo         <- metadata.labels['app']
#   CPU_LIMIT=8                 <- no CPU limit set: node allocatable (8 CPUs)
#   CPU_REQ_M=125               <- divisor 1m
#   HOST_IP=192.168.58.2        <- the node
#   MEM_REQ_MI=32               <- divisor 1Mi
#   POD_IPS=10.244.0.40
kubectl run lbls --image=busybox:1.36 --dry-run=server -o name \
  --overrides='{"spec":{"containers":[{"name":"lbls","image":"busybox:1.36","env":[{"name":"L","valueFrom":{"fieldRef":{"fieldPath":"metadata.labels"}}}]}]}}'
#   … fieldRef.fieldPath: Unsupported value: "metadata.labels": supported values: "metadata.name", …   <- whole maps only as files
```

## Cleanup
```bash
./cleanup.sh
```
