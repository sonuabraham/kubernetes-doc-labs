# The kubectl command-line tool – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/kubectl/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **kubectl** | The main CLI for creating, inspecting, updating and deleting objects. It's **only an API client**: every command becomes HTTP requests to the API server (see `../kubernetes-api`). |
| **kubeconfig** | Defines clusters, users and **contexts** (cluster + user + optional namespace). Default file `$HOME/.kube/config`. Override with the `KUBECONFIG` env var or `--kubeconfig`. `kubectl config use-context` switches clusters. |
| **In-cluster** | Inside a Pod there's no kubeconfig. kubectl uses the mounted **ServiceAccount token**, limited by RBAC. |
| **Categories** | Manage (`apply`, `create`, `delete`), inspect (`get`, `describe`, `events`, `top`), debug (`logs`, `exec`, `port-forward`, `debug`), cluster ops (`cordon`, `drain`, `uncordon`), script (`-o json/yaml/jsonpath/custom-columns`). |
| **Declarative first** | Use `kubectl apply` with version-controlled files for production. Imperative `create`/`run` are for experiments (see `../working-with-objects/object-management`). |
| **Plugins** | Any executable named `kubectl-<name>` on `PATH` becomes `kubectl <name>`. A dash in the file name means a sub-command: `kubectl-a-b` → `kubectl a b`. Install community plugins with **Krew**. |
| **Version skew** | kubectl supports **±1 minor version** against the control plane. |

## The demo app
[00-demo-app.yaml](00-demo-app.yaml) is namespace `kubectl-demo` with Deployment `web` (2× nginx) and Service `web`.
[01-kubectl-in-a-pod.yaml](01-kubectl-in-a-pod.yaml) adds ServiceAccount `ci` (read pods and deployments only) and a Job that runs `registry.k8s.io/kubectl:v1.37.0` inside the cluster.
[plugins/](plugins/) holds two tiny plugins, `kubectl podcount` and `kubectl ctxinfo`.

---

## Step 1
```bash
cd concepts/overview/kubectl
kubectl apply -f 00-demo-app.yaml
```

## Lab 1 – Version skew
```bash
kubectl version
```
On this machine:
```
Client Version: v1.35.10
Server Version: v1.37.0
Warning: version difference between client (1.35) and server (1.37) exceeds the supported minor version skew of +/-1
```
A two-minor-version gap is **unsupported**: new fields can be dropped or rejected, and some commands behave strangely. Two fixes:
```bash
minikube kubectl -- version          # minikube downloads a kubectl that matches the cluster (v1.37.0)
alias kubectl="minikube kubectl --"  # use it for this shell
# or upgrade the snap: sudo snap refresh kubectl --channel=1.37/stable
```

## Lab 2 – kubeconfig, contexts, KUBECONFIG
```bash
ls ~/.kube/config
kubectl config view --minify            # only the current context; certificates redacted
kubectl config get-contexts             # minikube (and any other clusters you have)
kubectl config current-context
```
Work on a **copy** so your real config isn't touched:
```bash
cp ~/.kube/config /tmp/kubectl-lab-kubeconfig
export KUBECONFIG=/tmp/kubectl-lab-kubeconfig                     # docs: the KUBECONFIG variable
kubectl config set-context demo --cluster=minikube --user=minikube --namespace=kubectl-demo
kubectl config use-context demo                                   # docs: switch contexts
kubectl get deploy                                                # web - namespace comes from the context
kubectl config get-contexts                                       # * demo ... kubectl-demo
unset KUBECONFIG
kubectl config current-context                                    # minikube - your real file never changed
kubectl --kubeconfig=/tmp/kubectl-lab-kubeconfig config current-context   # docs: the --kubeconfig flag -> demo
```

## Lab 3 – Every command is an HTTP request
```bash
kubectl get deploy web -n kubectl-demo -v=6 2>&1 | grep Response
#   "Response" verb="GET" url="https://192.168.58.2:8443/apis/apps/v1/namespaces/kubectl-demo/deployments/web" status="200 OK"
kubectl scale deploy web -n kubectl-demo --replicas=3 -v=8 2>&1 | grep -E 'Request Body|verb="PATCH"' | cut -c1-200
kubectl logs deploy/web -n kubectl-demo -v=6 2>&1 | grep Response | cut -c1-160   # logs are an API call too (pods/log subresource)
```

## Lab 4 – kubectl inside a Pod (in-cluster auth)
```bash
kubectl apply -f 01-kubectl-in-a-pod.yaml -f 02-kubectl-in-a-pod-forbidden.yaml
kubectl wait --for=condition=Complete job/ci-kubectl -n kubectl-demo --timeout=120s
kubectl logs job/ci-kubectl -n kubectl-demo
#   deployment.apps/web
#   pod/...                                   <- no kubeconfig: it used the ServiceAccount token
kubectl logs job/ci-kubectl-secrets -n kubectl-demo
#   Error from server (Forbidden): secrets is forbidden: User "system:serviceaccount:kubectl-demo:ci" cannot list resource "secrets" ...
kubectl auth can-i list secrets -n kubectl-demo --as=system:serviceaccount:kubectl-demo:ci    # no
```

## Lab 5 – The five categories
**Manage**
```bash
kubectl apply -f 00-demo-app.yaml                  # declarative (unchanged)
kubectl set image deploy/web nginx=nginx:1.27-alpine -n kubectl-demo
kubectl rollout status deploy/web -n kubectl-demo
```
**Inspect**
```bash
kubectl get all -n kubectl-demo
kubectl describe deploy web -n kubectl-demo
kubectl events -n kubectl-demo --types=Normal | tail -5
kubectl top pods -n kubectl-demo                   # needs metrics-server (minikube addons enable metrics-server)
```
**Debug**
```bash
kubectl logs deploy/web -n kubectl-demo --tail=3
kubectl exec deploy/web -n kubectl-demo -- nginx -v
kubectl port-forward svc/web 8080:80 -n kubectl-demo &   curl -s localhost:8080 | head -4 ; kill %1
kubectl debug -it deploy/web -n kubectl-demo --image=busybox:1.36 --target=nginx -- ps   # ephemeral container
```
**Cluster operations** (single-node minikube, so be careful)
```bash
kubectl cordon minikube
kubectl get node minikube                          # STATUS Ready,SchedulingDisabled - new pods stay Pending
kubectl drain minikube --ignore-daemonsets --delete-emptydir-data --dry-run=server
#   error: ... cannot delete Pods that declare no controller (use --force to override): kube-system/storage-provisioner
kubectl uncordon minikube
```
**Script and automate**
```bash
kubectl get pods -n kubectl-demo -o custom-columns=POD:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName
kubectl get deploy web -n kubectl-demo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get pods -n kubectl-demo -o json | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name'
kubectl wait --for=condition=Available deploy/web -n kubectl-demo --timeout=60s && echo ready
```

## Lab 6 – Plugins
```bash
export PATH=$PWD/plugins:$PATH
kubectl plugin list
#   The following compatible plugins are available:
#   .../plugins/kubectl-ctxinfo
#   .../plugins/kubectl-podcount
kubectl podcount -n kubectl-demo
#   1 Failed  (the forbidden job)   3 Running   1 Succeeded
kubectl ctxinfo
#   context=minikube cluster=minikube user=minikube namespace=default
```
Rename `kubectl-ctxinfo` to `kubectl-ctx-info` and it runs as `kubectl ctx info`, not `kubectl ctx-info`. To get a dash in the command name, use `_` in the file name: `kubectl-ctx_info` → `kubectl ctx-info`.
Krew (optional): https://krew.sigs.k8s.io/ → `kubectl krew install neat`, then `kubectl get deploy web -o yaml | kubectl neat`.

---

## Useful commands
```bash
kubectl config get-contexts | use-context <ctx> | set-context --current --namespace=<ns>
kubectl explain <kind>.<field>
kubectl api-resources
kubectl <cmd> -v=6                       # see the HTTP calls
kubectl <cmd> --dry-run=server -o yaml   # what the server would store
```

## Cleanup
```bash
./cleanup.sh      # uncordons the node (just in case), deletes kubectl-demo and the kubeconfig copy
```
