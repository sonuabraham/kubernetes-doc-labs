# Deploy and Access the Kubernetes Dashboard – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/

> Runs on the default **minikube** cluster. Files: [dashboard-adminuser.yaml](dashboard-adminuser.yaml) (the Dashboard project's sample
> admin user + a read-only `viewer` that is **not from the docs**), [helm.sh](helm.sh) (helm from its container image: no local install needed).
>
> **Found (2026-11):**
> 1. **The Kubernetes Dashboard project is retired.** `github.com/kubernetes/dashboard` now redirects to `kubernetes-retired/dashboard`,
>    and the docs' repo `https://kubernetes.github.io/dashboard/` gives **404** (`helm repo add … not a valid chart repository`).
>    The last chart, 7.14.0, is still a GitHub release asset, and this lab installs that. Expect no more fixes. For a maintained web UI,
>    look at an active project such as Headlamp (kubernetes-sigs).
> 2. "The container image specification must end with a colon" (wizard section) is wrong; an image like `nginx:1.27` works.
> 3. minikube also has its own `minikube dashboard` addon (older Dashboard v2, different Service names). This lab follows the docs' Helm way.

## Key ideas (read first)

| Piece | Meaning |
|---|---|
| Chart 7.x | 5 Deployments: `web`, `api`, `auth`, `metrics-scraper`, and **kong** (gateway in front, HTTPS on 443) |
| Access | `kubectl port-forward svc/kubernetes-dashboard-kong-proxy 8443:443` → https://localhost:8443 (self-signed) |
| Login | bearer token only; the Dashboard has no rights of its own: it acts **with your token's RBAC** |
| Sample user | `admin-user` bound to `cluster-admin`: lab only |

---

## Lab 1 – Install (docs, via the release asset)
```bash
cd tasks/access-application-cluster/web-ui-dashboard
./helm.sh repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
#   Error: looks like "https://kubernetes.github.io/dashboard/" is not a valid chart repository or cannot be reached: … 404 Not Found
./helm.sh upgrade --install kubernetes-dashboard \
  https://github.com/kubernetes-retired/dashboard/releases/download/kubernetes-dashboard-7.14.0/kubernetes-dashboard-7.14.0.tgz \
  --create-namespace --namespace kubernetes-dashboard
#   Congratulations! You have just installed Kubernetes Dashboard in your cluster. …
kubectl -n kubernetes-dashboard get pods,svc            # ~1 min until all Running
#   kubernetes-dashboard-api / -auth / -kong / -metrics-scraper / -web
#   service/kubernetes-dashboard-kong-proxy   ClusterIP   …   443/TCP
```

## Lab 2 – Access with tokens (docs + viewer)
```bash
kubectl apply -f dashboard-adminuser.yaml
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443 &
kubectl -n kubernetes-dashboard create token admin-user          # paste into the login page at https://localhost:8443
```
Without a browser, the same checks through the Dashboard's own API (not from the docs):
```bash
curl -sk https://localhost:8443/ | grep -o '<title>[^<]*</title>'         # <title>Kubernetes Dashboard</title>
curl -sk -o /dev/null -w '%{http_code}\n' https://localhost:8443/api/v1/namespace     # 401   (no token)
ADMIN=$(kubectl -n kubernetes-dashboard create token admin-user); VIEW=$(kubectl -n kubernetes-dashboard create token viewer)
curl -sk -H "Authorization: Bearer $ADMIN" https://localhost:8443/api/v1/namespace | jq -r '[.namespaces[].objectMeta.name]|join(",")'
#   default,kube-node-lease,kube-public,kube-system,kubernetes-dashboard
curl -sk -H "Authorization: Bearer $VIEW" https://localhost:8443/api/v1/deployment/kube-system | jq -r '[.deployments[].objectMeta.name]|join(",")'
#   coredns,metrics-server,snapshot-controller
curl -sk -H "Authorization: Bearer $VIEW" https://localhost:8443/api/v1/secret/kube-system | jq -c '.errors[0].ErrStatus.reason'
#   "Forbidden"           <- the "view" role can't read Secrets: the Dashboard enforces your RBAC, not its own
```

## Lab 3 – The deploy wizard, as an API call (not from the docs)
What the **CREATE** wizard sends (app name, image, pods, internal Service, labels, description):
```bash
CSRF=$(curl -sk -H "Authorization: Bearer $ADMIN" https://localhost:8443/api/v1/csrftoken/appdeployment | jq -r .token)
curl -sk -X POST -H "Authorization: Bearer $ADMIN" -H "X-CSRF-TOKEN: $CSRF" -H 'Content-Type: application/json' \
  https://localhost:8443/api/v1/appdeployment -d '{"containerImage":"nginx:1.27","name":"dash-nginx","namespace":"default","replicas":2,
  "portMappings":[{"port":80,"targetPort":80,"protocol":"TCP"}],"isExternal":false,
  "labels":[{"key":"app","value":"dash-nginx"},{"key":"tier","value":"frontend"}],"description":"created through the Dashboard API","runAsPrivileged":false,"variables":[]}'
kubectl get deploy,svc -l app=dash-nginx           # deployment.apps/dash-nginx 2 replicas + service/dash-nginx ClusterIP 80/TCP
kubectl get deploy dash-nginx -o jsonpath='{.metadata.annotations.description}'      # created through the Dashboard API
```
As the docs say: **Description** becomes an annotation, labels go on Deployment + Service + Pods, the Service is named after the app.

## Cleanup
```bash
./cleanup.sh       # stops a port-forward started with its PID in $PF_PID_FILE, uninstalls the chart, deletes the namespace
```
