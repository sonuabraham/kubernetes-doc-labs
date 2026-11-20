# Enforcing Pod Security Standards – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/best-practices/enforcing-pod-security-standards/

> The page is guidance for Pod Security Admission (PSA): label every namespace, least privilege, use `warn`/`audit` toward the level you
> want to `enforce`, and pin versions carefully. Each recommendation is tried on the default **minikube** (v1.37). All files are NOT from
> the docs (the page has none): [namespaces.yaml](namespaces.yaml), [probe-host-pod.yaml](probe-host-pod.yaml).
>
> **Found / worth knowing:**
> - A real rule change between versions, for the page's version-pinning advice: **baseline gained the "probe or lifecycle host" check in
>   v1.34**. A Pod with `readinessProbe.httpGet.host: 10.0.0.1` is admitted under `baseline:v1.30`…`v1.33` and forbidden under
>   `baseline:v1.34`, `v1.35`, `latest`.
> - **Enforcement applies to Pods only.** A Deployment with a privileged template is created (with just the `warn`-level warning); then the
>   ReplicaSet can't create Pods: `FailedCreate … violates PodSecurity "baseline:latest": privileged`, and the Deployment stays `0/1`.
>   That's why the page recommends `warn` at the enforce level (or higher): it surfaces the problem on the Deployment itself.
> - "Unlabeled namespaces should only indicate that they've yet to be evaluated": on this minikube *all four* built-in namespaces are
>   unlabeled (cluster default = privileged everywhere).
> - `audit` mode writes annotations into audit events; minikube has no audit log configured, so only `warn` and `enforce` are visible here.

## Key ideas (read first)

| Recommendation | In practice |
|---|---|
| Configure all namespaces | no label = not evaluated; bulk-label as in [tasks/…/enforce-standards-namespace-labels](../../../tasks/configure-pod-container/enforce-standards-namespace-labels/) |
| Least privilege | `restricted` where possible; `privileged` namespaces need tight RBAC and documented reasons |
| Multi-mode | `enforce` = what you can live with now, `warn` + `audit` = where you want to be |
| Version pinning | `enforce-version: v1.xx` keeps behaviour stable on upgrades; `warn`/`audit` at `latest` show what newer rules would reject |
| Alternatives | Kubewarden, Kyverno, OPA Gatekeeper (third party); ValidatingAdmissionPolicy (built-in, see [tutorials/cluster-management/admission-policies](../../../tutorials/cluster-management/admission-policies/)) |

## Lab 1 – Which namespaces are unconfigured?
```bash
kubectl get ns -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn,pod-security.kubernetes.io/audit
#   default, kube-node-lease, kube-public, kube-system – all empty
```

## Lab 2 – Multi-mode (enforce baseline, warn/audit restricted)
```bash
kubectl apply -f namespaces.yaml
kubectl -n pss-multimode create deployment web --image=nginx
#   Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false …, unrestricted capabilities …,
#            runAsNonRoot != true …, seccompProfile …
#   deployment.apps/web created                                      <- allowed (baseline), but you know what to fix for restricted
kubectl -n pss-multimode run priv --image=nginx --privileged
#   Error from server (Forbidden): pods "priv" is forbidden: violates PodSecurity "baseline:latest": privileged …
# a Deployment with a privileged template:
#   Warning: would violate PodSecurity "restricted:latest": privileged … / deployment.apps/priv-dep created
kubectl -n pss-multimode get deploy priv-dep          # 0/1
kubectl -n pss-multimode get events --field-selector reason=FailedCreate
#   ReplicaSet/priv-dep-…: Error creating: pods "…" is forbidden: violates PodSecurity "baseline:latest": privileged …
```

## Lab 3 – Pinned enforce version, warn/audit at latest
```bash
# which baseline versions allow a probe with an explicit host? (dry-run, one namespace relabelled per version)
#   baseline:v1.30 … v1.33 → pod/probe-host created (server dry run)
#   baseline:v1.34, v1.35, latest → Forbidden
kubectl apply -n pss-pinned -f probe-host-pod.yaml     # namespace: enforce baseline v1.33, warn/audit baseline latest
#   Warning: would violate PodSecurity "baseline:latest": probe or lifecycle host (container "c" uses probe or lifecycle host "10.0.0.1")
#   pod/probe-host created                               <- still allowed, but flagged before you move enforce to latest
```

## Cleanup
```bash
./cleanup.sh       # namespaces pss-multimode, pss-pinned (and pss-probe from the version scan)
```
