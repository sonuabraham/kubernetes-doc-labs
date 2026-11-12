# Configuration – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/configuration/

> Sub-pages: [configmap](configmap/), [secret](secret/), [manage-resources-containers](manage-resources-containers/), [organize-cluster-access-kubeconfig](organize-cluster-access-kubeconfig/), [windows-resource-management](windows-resource-management/).

## Key ideas (read first)

| What you configure | Mechanism | Lab |
|---|---|---|
| App settings (non-secret) | **ConfigMap** → env, files, args | [configmap](configmap/) |
| Credentials, keys, tokens | **Secret** (base64, not encrypted by default) | [secret](secret/) |
| How much CPU/memory/… a container gets | **requests / limits**, pod-level resources, extended resources | [manage-resources-containers](manage-resources-containers/) |
| How *you* reach clusters | **kubeconfig**: clusters, users, contexts | [organize-cluster-access-kubeconfig](organize-cluster-access-kubeconfig/) |
| Windows specifics | job objects, no OOM killer, reservations | [windows-resource-management](windows-resource-management/) |

Common thread: **separate configuration from the image**, so the same artifact runs in dev, test and prod with different ConfigMaps, Secrets and resources.

---

## Lab – One image, two environments
```bash
cd concepts/configuration
kubectl apply -f 00-two-envs.yaml
kubectl logs -n cfg-dev deploy/app ; kubectl logs -n cfg-prod deploy/app
#   env=dev log_level=debug db_password_len=6 cpu_limit=1
#   env=prod log_level=warn db_password_len=22 cpu_limit=2
```
Same image and Deployment template. Only the namespace's ConfigMap, Secret and the resource limits differ.

## Cleanup
```bash
./cleanup.sh
```
