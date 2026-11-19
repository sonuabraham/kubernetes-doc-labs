# Performing a Rolling Update – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/

> Module 6 of [Learn Kubernetes Basics](../../). Continues with the 2-replica `kubernetes-bootcamp` Deployment and Service from module 5.
> Commands as in the docs.
>
> **Notes:**
> - Run in module order, `kubectl expose deployment/kubernetes-bootcamp --type="NodePort" --port 8080` fails with
>   `Error from server (AlreadyExists): services "kubernetes-bootcamp" already exists` (module 5's LoadBalancer Service is still there).
>   That's harmless: the `NODE_PORT` command just reads the existing Service.
> - Old Pods stay `Terminating` for ~30 s: the Node.js server runs as PID 1 and ignores SIGTERM, so each Pod waits out its grace period.
> - `gcr.io/google-samples/kubernetes-bootcamp:v10` doesn't exist **on purpose**; that's the broken update.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `kubectl set image` | new Pod template → new ReplicaSet → rolling update (old Pods replaced gradually) |
| `rollout status` | waits until the update is done |
| Broken image | new Pods hang in `ErrImagePull`; old Pods keep serving (default `maxUnavailable` 25%) |
| `rollout undo` | back to the previous revision |

## Lab
```bash
kubectl get deployments            # 2/2
kubectl get pods
kubectl describe pods | grep Image:              # gcr.io/google-samples/kubernetes-bootcamp:v1 (×2)
kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=docker.io/jocatalin/kubernetes-bootcamp:v2
kubectl get pods                   # new Pod ContainerCreating, old ones Running/Terminating
kubectl expose deployment/kubernetes-bootcamp --type="NodePort" --port 8080
#   Error from server (AlreadyExists): services "kubernetes-bootcamp" already exists      <- see notes
export NODE_PORT="$(kubectl get services/kubernetes-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}')"
curl http://"$(minikube ip):$NODE_PORT"
#   Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5b97597885-h69jk | v=2
#   (right after the update a v=1 answer can still appear while the last old Pod terminates)
kubectl rollout status deployments/kubernetes-bootcamp     # deployment "kubernetes-bootcamp" successfully rolled out
kubectl describe pods | grep Image:                        # docker.io/jocatalin/kubernetes-bootcamp:v2
kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=gcr.io/google-samples/kubernetes-bootcamp:v10
kubectl get deployments            # 2/2   UP-TO-DATE 1   AVAILABLE 2
kubectl get pods                   # kubernetes-bootcamp-556487b4d4-…   0/1   ErrImagePull     + the two v2 Pods Running
kubectl describe pods | grep Failed
#   Failed to pull image "gcr.io/google-samples/kubernetes-bootcamp:v10": rpc error: code = NotFound …
kubectl rollout undo deployments/kubernetes-bootcamp       # deployment.apps/kubernetes-bootcamp rolled back
kubectl get pods                   # the v10 Pod is gone, two v2 Pods Running
kubectl describe pods | grep Image:                        # docker.io/jocatalin/kubernetes-bootcamp:v2
kubectl delete deployments/kubernetes-bootcamp services/kubernetes-bootcamp
```
Then stop the `kubectl proxy` from module 2 (Ctrl+C), or run [../../cleanup.sh](../../cleanup.sh).
