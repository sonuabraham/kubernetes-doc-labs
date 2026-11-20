# Namespaces Walkthrough – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/cluster-management/namespaces-walkthrough/

> Runs on the default **minikube**. [namespace-dev.yaml](namespace-dev.yaml), [namespace-prod.yaml](namespace-prod.yaml) and
> [snowflake-deployment.yaml](snowflake-deployment.yaml) are the docs examples **verbatim**.
>
> **Notes:**
> - The page's cluster/user name `lithe-cocoa-92103_kubernetes` is an old GKE example. Here both are `minikube`. Read them from your
>   context: `kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}'` (and `.user`).
> - Its sample `kubectl config view` output shows a bearer token and a basic-auth password. Basic auth was removed from Kubernetes long
>   ago; minikube uses client certificates (`client-certificate: ~/.minikube/profiles/minikube/client.crt`).
> - Namespace labels: every namespace also gets `kubernetes.io/metadata.name=<name>` automatically, so `default` isn't `<none>`.
> - `registry.k8s.io/serve_hostname` (no tag) still pulls and works.
> - **The page has no cleanup**, and it leaves `dev`/`prod` contexts in `~/.kube/config` with `prod` as the current context.
>   [cleanup.sh](cleanup.sh) switches back to `minikube` and removes them.
> - "Users interacting with one namespace do not see the content in another namespace" is about **names** in API listings. NOT from the
>   docs: a Pod in `production` reaches a Service in `development` (`snowflake.development:9376`). Network isolation needs NetworkPolicy,
>   and access control needs RBAC per namespace.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Namespace | a name scope for Pods, Services, Deployments …; the same name can exist once per namespace |
| Context | cluster + user + **default namespace** in kubeconfig; `kubectl config set-context` / `use-context` |
| `kubectl get` | lists only the current context's namespace unless `-n` / `-A` |
| Not isolation | no network or permission boundary by itself |

## Lab
```bash
kubectl get namespaces                            # default, kube-node-lease, kube-public, kube-system
kubectl create -f namespace-dev.yaml              # namespace/development created
kubectl create -f namespace-prod.yaml             # namespace/production created
kubectl get namespaces --show-labels
#   development   Active   1s   kubernetes.io/metadata.name=development,name=development
#   production    Active   1s   kubernetes.io/metadata.name=production,name=production
kubectl config view                               # (shown with --minify above: cluster minikube, user minikube, client cert files)
kubectl config current-context                    # minikube
kubectl config set-context dev --namespace=development --cluster=minikube --user=minikube     # Context "dev" created.
kubectl config set-context prod --namespace=production --cluster=minikube --user=minikube     # Context "prod" created.
kubectl config get-contexts
#   dev    minikube   minikube   development
#   *  minikube …                default
#   prod   minikube   minikube   production
kubectl config use-context dev                    # Switched to context "dev".
kubectl config current-context                    # dev
kubectl apply -f snowflake-deployment.yaml
kubectl get deployment                            # snowflake   2/2   2   2
kubectl get pods -l app=snowflake                 # snowflake-7d95b6d667-ljgx2 / -nmvtq   Running
kubectl config use-context prod
kubectl get deployment                            # No resources found in production namespace.
kubectl get pods                                  # No resources found in production namespace.
kubectl create deployment cattle --image=registry.k8s.io/serve_hostname --replicas=5
kubectl get deployment                            # cattle   5/5   5   5
kubectl get pods -l app=cattle                    # 5 × cattle-6896b4f44c-…   Running
```
NOT from the docs – names are separated, the network isn't:
```bash
kubectl --context dev expose deployment snowflake --port=9376
kubectl --context prod run probe --image=busybox:1.36 --restart=Never -- sh -c 'for i in 1 2 3; do wget -qO- http://snowflake.development:9376; echo; done'
kubectl --context prod logs probe                 # snowflake-7d95b6d667-ljgx2 / -nmvtq / -nmvtq   <- from production into development
kubectl get pods -A -l 'app in (snowflake,cattle)'    # 2 in development, 5 in production   (-A sees across namespaces)
```

## Cleanup
```bash
./cleanup.sh      # use-context minikube; delete-context dev/prod; delete namespaces development, production
```
