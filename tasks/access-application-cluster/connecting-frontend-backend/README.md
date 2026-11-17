# Connect a Frontend to a Backend Using Services – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/connecting-frontend-backend/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [backend-deployment.yaml](backend-deployment.yaml),
> [backend-service.yaml](backend-service.yaml), [frontend-deployment.yaml](frontend-deployment.yaml), [frontend-service.yaml](frontend-service.yaml),
> [frontend-nginx.conf](frontend-nginx.conf), [Dockerfile](Dockerfile) (how the frontend image was built).
> Not from the docs: [frontend-configmap-variant.yaml](frontend-configmap-variant.yaml).
>
> **Found:**
> 1. The cleanup command `kubectl delete services frontend backend` fails (`services "backend" not found`). The backend Service is
>    called **`hello`**, so the `hello` Service is left behind.
> 2. On minikube the `LoadBalancer` stays `<pending>` until `minikube tunnel` runs, and the tunnel needs **sudo** for its route
>    (`router: error adding Route: sudo: A terminal is required to authenticate`). Every LoadBalancer Service also gets a NodePort,
>    and that works without sudo.
> 3. The sample `describe` output is from 2016. Current: `Labels: <none>`, `25% max unavailable, 25% max surge`, and the named port is shown as `80/TCP (http)`.

## Key ideas (read first)

| Piece | Role |
|---|---|
| backend Deployment (3×) | `hello-go-gke` answers `{"message":"Hello"}` on port `http` (80) |
| Service `hello` | ClusterIP + DNS name `hello`; `targetPort: http` refers to the **named** container port |
| frontend nginx | `upstream Backend { server hello; }` → `proxy_pass http://Backend` |
| Service `frontend` | `type: LoadBalancer` = NodePort + cloud LB (no LB on plain minikube) |

---

## Lab 1 – Backend (docs)
```bash
cd tasks/access-application-cluster/connecting-frontend-backend
kubectl apply -f backend-deployment.yaml
kubectl describe deployment backend | grep -E 'Selector|Replicas|Image|Port:'
#   Selector:   app=hello,tier=backend,track=stable
#   Replicas:   3 desired | 3 updated | 3 total | 3 available | 0 unavailable
#   Image:      gcr.io/google-samples/hello-go-gke:1.0
#   Port:       80/TCP (http)
kubectl apply -f backend-service.yaml
kubectl get endpointslices -l kubernetes.io/service-name=hello -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} {end}'
#   10.244.0.135 10.244.0.134 10.244.0.136
```

## Lab 2 – Frontend (docs)
```bash
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml
kubectl get service frontend --watch
#   frontend   LoadBalancer   10.108.208.61   <pending>   80:30641/TCP   … stays pending on minikube
```
Reach it anyway:
```bash
curl http://$(minikube ip):30641          # {"message":"Hello"}   <- the NodePort part of the LoadBalancer Service
# with a terminal and sudo:  minikube tunnel   (in another window) → EXTERNAL-IP is filled → curl http://<EXTERNAL-IP>
```

## Lab 3 – Config from a ConfigMap (the docs' note, not from the docs)
```bash
kubectl create configmap frontend-nginx-conf --from-file=frontend-nginx.conf
kubectl apply -f frontend-configmap-variant.yaml       # stock nginx:1.27 + the same conf, NodePort 30081
curl http://$(minikube ip):30081                       # {"message":"Hello"}
kubectl exec deploy/frontend-cm -- getent hosts hello  # 10.101.223.223  hello.default.svc.cluster.local
```
Changing the proxy config is now a ConfigMap edit + rollout restart, not an image rebuild.

## Lab 4 – The docs' cleanup
```bash
kubectl delete services frontend backend
#   service "frontend" deleted
#   Error from server (NotFound): services "backend" not found
kubectl delete deployment frontend backend
./cleanup.sh                                           # also removes Service "hello" and the ConfigMap variant
```
