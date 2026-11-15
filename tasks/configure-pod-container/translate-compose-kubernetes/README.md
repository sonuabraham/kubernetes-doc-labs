# Translate a Docker Compose File to Kubernetes Resources – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/translate-compose-kubernetes/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs. Uses **kompose v1.34.0**, the version the
> docs pin, downloaded into `bin/` (gitignored) and checked against the release's `SHA256_SUM`.
> Files: [docker-compose.yml](docker-compose.yml) (docs, **verbatim**). The generated manifests are committed in [out/](out/),
> [out-alt/](out-alt/) and [out-extras/](out-extras/). Not from the docs: [docker-compose-extras.yml](docker-compose-extras.yml).
>
> **Found:** kompose renames `web_service` → `web-service` for the Deployment, PVC and Ingress, but **not for the Service**.
> That object stays `web_service`, and the API server rejects it.

## Key ideas (read first)

| Compose | Kubernetes (kompose default) |
|---|---|
| a service | Deployment (`--controller deployment\|daemonSet\|replicationController`) |
| `ports:` | Service (no `ports` means no Service). Type set by the label `kompose.service.type`. |
| `restart: on-failure` / `no` | a bare **Pod** with `restartPolicy: OnFailure` / `Never` |
| named volume | PVC + Deployment strategy **Recreate** |
| label `kompose.service.expose: host` | Ingress for that host |
| `container_name`, `command`, `environment` | container name, `args`, `env` |

It's a starting point for a migration, not a finished design: no probes, resources or security context are generated.

---

## Step 0 – Install kompose (docs: GitHub download)
```bash
cd tasks/configure-pod-container/translate-compose-kubernetes
mkdir -p bin
curl -L https://github.com/kubernetes/kompose/releases/download/v1.34.0/kompose-linux-amd64 -o bin/kompose
curl -sL https://github.com/kubernetes/kompose/releases/download/v1.34.0/SHA256_SUM | grep 'kompose-linux-amd64$'
sha256sum bin/kompose          # c58d0e63ef6bf8a98fc9840025b943f50f2d0ad807b2f8d55db92cea869ee171 - must match
chmod +x bin/kompose; bin/kompose version        # 1.34.0 (cbf2835db)
```
(The docs then `sudo mv` it to `/usr/local/bin`. Keeping it local avoids touching the system.)

## Lab 1 – Convert and deploy the docs' compose file
```bash
mkdir -p out && cd out
../bin/kompose convert -f ../docker-compose.yml
#   INFO Kubernetes file "redis-leader-service.yaml" created
#   INFO Kubernetes file "redis-replica-service.yaml" created
#   INFO Kubernetes file "web-tcp-service.yaml" created
#   INFO Kubernetes file "redis-leader-deployment.yaml" created
#   INFO Kubernetes file "redis-replica-deployment.yaml" created
#   INFO Kubernetes file "web-deployment.yaml" created
kubectl apply -f web-tcp-service.yaml,redis-leader-service.yaml,redis-replica-service.yaml,web-deployment.yaml,redis-leader-deployment.yaml,redis-replica-deployment.yaml
kubectl rollout status deploy/web deploy/redis-leader deploy/redis-replica
```
See [out/web-tcp-service.yaml](out/web-tcp-service.yaml): `type: LoadBalancer` from the label, selector `io.kompose.service: web`.

## Lab 2 – Use the app
```bash
kubectl get svc web-tcp                     # LoadBalancer  EXTERNAL-IP <pending>  8080:30330/TCP  (no tunnel)
URL=$(minikube service web-tcp --url)       # http://192.168.58.2:30330 via the NodePort
curl -s $URL | grep title                   # <title>Kompose Guestbook</title>
curl -s "$URL/rpush/guestbook/hello-from-kompose"
curl -s "$URL/lrange/guestbook"             # ["hello-from-kompose"]
kubectl exec deploy/redis-replica -- redis-cli info replication | grep -E 'role|master_host|master_link_status'
#   role:slave   master_host:redis-leader   master_link_status:up       <- the compose "command:" became args
kubectl exec deploy/redis-replica -- redis-cli lrange guestbook 0 -1   # hello-from-kompose (replicated)
```
`minikube tunnel` (in another terminal) would give the LoadBalancer an external IP.

## Lab 3 – Alternative conversions (docs)
```bash
mkdir -p out-alt && cd out-alt
../bin/kompose convert -f ../docker-compose.yml -j -o json/                      # *.json
../bin/kompose convert -f ../docker-compose.yml --controller daemonSet -o ds/    # *-daemonset.yaml
../bin/kompose convert -f ../docker-compose.yml -c -o chart                      # Helm chart skeleton
../bin/kompose convert -f ../docker-compose.yml --daemon-set -o ds/
#   Flag --daemon-set has been deprecated, use --controller           <- the docs' flag (same for --replication-controller)
```

## Lab 4 – Restart, volumes, labels, underscores (not from the docs)
```bash
mkdir -p out-extras && cd out-extras
../bin/kompose convert -f ../docker-compose-extras.yml
#   INFO Service name in docker-compose has been changed from "web_service" to "web-service"
#   WARN Service "pival" won't be created because 'ports' is not specified
#   INFO Kubernetes file "web_service-service.yaml" created          <- note the underscore
#   INFO Kubernetes file "pival-pod.yaml" created
#   INFO Kubernetes file "web-service-deployment.yaml" created
#   INFO Kubernetes file "web-service-ingress.yaml" created
#   INFO Kubernetes file "web-data-persistentvolumeclaim.yaml" created
```
| Output | Checks the page's rule |
|---|---|
| `pival-pod.yaml`: `kind: Pod`, `restartPolicy: OnFailure` | `restart: on-failure` gives a Pod, not a controller |
| `web-service-deployment.yaml`: `strategy: type: Recreate`, `claimName: web-data` | volume gives a PVC + Recreate |
| `web_service-service.yaml`: `type: NodePort` | label `kompose.service.type: nodeport` |
| `web-service-ingress.yaml`: `host: web.example.com` | label `kompose.service.expose` |
```bash
kubectl apply -f pival-pod.yaml; kubectl logs pival | head -c 40      # 3.14159265358979323846264338327950288419
kubectl apply --dry-run=server -f web_service-service.yaml
#   The Service "web_service" is invalid: metadata.name: Invalid value: "web_service": a lowercase RFC 1123 label must consist of …
```
Its selector *was* renamed (`io.kompose.service: web-service`), only `metadata.name` wasn't. Fix it by hand, or avoid `_`.

## Useful commands
```bash
bin/kompose convert --help
bin/kompose convert -f docker-compose.yml --stdout | kubectl apply --dry-run=server -f -
```

## Cleanup
```bash
./cleanup.sh       # the docs' kubectl delete -f … + the pival Pod
```
