# Apply Pod Security Standards at the Namespace Level – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/security/ns-level-pss/

> The page creates a kind cluster `psa-ns-level`. Namespace labels need no API server configuration, so this lab runs on the **default
> minikube** (v1.37.0) instead; kind isn't installed here. Every `kubectl` command is as in the docs.
> Files, **verbatim**: [example-baseline-pod.yaml](example-baseline-pod.yaml),
> [kind-with-namespace-level-baseline-pod-security.sh](kind-with-namespace-level-baseline-pod-security.sh) (the "What's next" script; needs kind).
>
> **Notes:**
> - "Set the kubectl context to the new cluster: `kubectl cluster-info --context kind-psa-ns-level`" doesn't set anything. `--context`
>   only applies to that one command. `kind create cluster` already switched the context.
> - `audit=restricted` writes audit annotations, which you don't see without an audit log (minikube has none by default).

## Key ideas (read first)

| Label | Effect |
|---|---|
| `pod-security.kubernetes.io/<mode>=<level>` | mode `enforce` / `warn` / `audit`; level `privileged` / `baseline` / `restricted` |
| `…/<mode>-version=latest` (or `v1.37`) | which version of the standard's checks to use |
| Per namespace | other namespaces are unaffected (`default` has no labels → privileged) |
| Labeling a namespace | the API server warns about **existing** Pods that would violate the new `enforce` level, but doesn't evict them |

## Lab
```bash
kubectl create ns example                                            # namespace/example created
kubectl label --overwrite ns example \
   pod-security.kubernetes.io/warn=baseline \
   pod-security.kubernetes.io/warn-version=latest                   # namespace/example labeled

# NOT from the docs – warn only: a privileged Pod is admitted, with a warning
kubectl -n example run priv --image=nginx --privileged
#   Warning: would violate PodSecurity "baseline:latest": privileged (container "priv" must not set securityContext.privileged=true)
#   pod/priv created
kubectl -n example delete pod priv --now

kubectl label --overwrite ns example \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest

kubectl apply -n example -f example-baseline-pod.yaml
#   Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" must set
#   securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (…capabilities.drop=["ALL"]), runAsNonRoot != true (…),
#   seccompProfile (…"RuntimeDefault" or "Localhost")
#   pod/nginx created
kubectl apply -n default -f example-baseline-pod.yaml
#   pod/nginx created                                                  <- no warning in default
```
NOT from the docs:
```bash
kubectl -n example run priv --image=nginx --privileged
#   Error from server (Forbidden): pods "priv" is forbidden: violates PodSecurity "baseline:latest": privileged (…)   <- now enforced
kubectl label --dry-run=server --overwrite ns example pod-security.kubernetes.io/enforce=restricted
#   Warning: existing pods in namespace "example" violate the new PodSecurity enforce level "restricted:latest"
#   Warning: nginx: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
```

## Cleanup
Docs: `kind delete cluster --name psa-ns-level`. Here:
```bash
./cleanup.sh            # deletes namespace example and pod default/nginx
```
