# Pod Security Admission – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/pod-security-admission/

> The page's only block is the label reference, kept verbatim in [labels-reference-excerpt.yaml](labels-reference-excerpt.yaml). [admission-config-example.yaml](admission-config-example.yaml) shows the static config for defaults and exemptions; it isn't applied here because that means editing the API server's flags.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **PodSecurity admission** | Built-in admission controller (GA, on by default) that enforces the [Pod Security Standards](../pod-security-standards/) **per namespace**. |
| **Labels** | `pod-security.kubernetes.io/<MODE>: <LEVEL>` + optional `<MODE>-version: v1.37 \| latest`. |
| **Modes** | `enforce`: reject the Pod. `warn`: user-facing warning, allowed. `audit`: annotation in the **audit log**, allowed. Each mode can use a different level. |
| **Workload resources** | `warn` and `audit` also check **templates** (Deployments, Jobs…) at create time. `enforce` only checks **Pods**, so a bad Deployment is created but its Pods are rejected (`FailedCreate` on the ReplicaSet). |
| **Existing Pods** | Never evicted. Labelling a namespace **warns** about current violators. |
| **Updates** | Metadata changes (except seccomp/AppArmor annotations), `activeDeadlineSeconds` and `tolerations` are exempt. Other updates to a violating Pod are checked. |
| **Exemptions** | Static config only: usernames, runtimeClassNames, namespaces. Exempting a **user** doesn't cover Pods made by controllers. |
| **Defaults** | Static config can set levels for unlabelled namespaces (default: privileged everywhere). |
| **Metrics** | `pod_security_evaluations_total`, `pod_security_exemptions_total`, `pod_security_errors_total` on the API server. |

---

## Step 1
```bash
cd concepts/security/pod-security-admission
kubectl apply -f 00-namespaces.yaml     # psa-modes: enforce=baseline, warn+audit=restricted ; psa-legacy: unlabelled
```

## Lab 1 – enforce vs warn
```bash
kubectl run plain -n psa-modes --image=busybox:1.36 -- sleep 3600
#   Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (...), unrestricted capabilities (...),
#            runAsNonRoot != true (...), seccompProfile (...)
#   pod/plain created                     <- passes enforce (baseline), only WARNED about restricted
```
`audit` writes `pod-security.kubernetes.io/audit-violations` into audit events. Audit logging is off on minikube (see `../cloud-native-security`), but the metric still counts the decisions (Lab 5).

## Lab 2 – Workload resources
```bash
kubectl apply -n psa-modes -f 01-workloads.yaml
#   Warning: would violate PodSecurity "restricted:latest": privileged (...), ...
#   deployment.apps/priv-deploy created   <- the Deployment is accepted
kubectl get rs -n psa-modes -l app=priv          # DESIRED 1  CURRENT 0
kubectl get events -n psa-modes --field-selector reason=FailedCreate -o custom-columns=M:.message | tail -1
#   Error creating: pods "priv-deploy-…" is forbidden: violates PodSecurity "baseline:latest": privileged (...)
```
Only `warn` and `audit` look at templates, so the warning on apply is your early signal.

## Lab 3 – Tightening a namespace that already has Pods
```bash
kubectl apply -n psa-legacy -f 01-workloads.yaml        # unlabelled = privileged: both run
kubectl label --dry-run=server --overwrite ns psa-legacy pod-security.kubernetes.io/enforce=restricted
#   Warning: existing pods in namespace "psa-legacy" violate the new PodSecurity enforce level "restricted:latest"
#   Warning: plain: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
#   Warning: priv-deploy-…: privileged, allowPrivilegeEscalation != false, ...
kubectl label --overwrite ns psa-legacy pod-security.kubernetes.io/enforce=baseline
kubectl get pods -n psa-legacy                           # both still Running - nothing is evicted
```
**Dry-run the label first.** That's the docs-recommended way to find out what would break.

## Lab 4 – Updates to violating Pods
```bash
P=$(kubectl get pod -n psa-legacy -l app=priv -o name)
kubectl label $P -n psa-legacy touched=yes                                           # allowed (metadata)
kubectl patch pod plain -n psa-legacy -p '{"spec":{"activeDeadlineSeconds":7200}}'   # allowed (exempt field)
kubectl patch $P -n psa-legacy -p '{"spec":{"containers":[{"name":"c","image":"busybox:1.37"}]}}'
#   Forbidden: violates PodSecurity "baseline:latest": privileged (...)      <- any other update is checked
kubectl delete $P -n psa-legacy
kubectl get events -n psa-legacy --field-selector reason=FailedCreate -o custom-columns=M:.message | tail -1
#   ... is forbidden: violates PodSecurity "baseline:latest": privileged     <- the replacement can't come back
```
That's the real migration risk: the next rollout, node drain or crash removes the old Pods for good.

## Lab 5 – Version pinning
```bash
kubectl create ns psa-ver
for v in v1.0 v1.18 v1.19 v1.22 latest; do
  kubectl label --overwrite ns psa-ver pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=$v
  kubectl run plain -n psa-ver --image=busybox:1.36 --dry-run=server 2>&1 | sed 's/.*PodSecurity //; s/ ([^)]*)//g'
done
#   "restricted:v1.0":  runAsNonRoot != true
#   "restricted:v1.18": allowPrivilegeEscalation != false, runAsNonRoot != true
#   "restricted:v1.19": allowPrivilegeEscalation != false, runAsNonRoot != true, seccompProfile
#   "restricted:v1.22": allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
#   "restricted:latest": (same as v1.22)
```
The standard grew over time. Pinning a version keeps an upgrade from suddenly rejecting Pods; `latest` picks up new rules on upgrade.

## Lab 6 – Metrics
```bash
kubectl get --raw /metrics | grep '^pod_security_evaluations_total' | grep -v ' 0$'
#   {decision="allow",mode="enforce",policy_level="baseline",...,resource="pod"} 28
#   {decision="deny",mode="audit",policy_level="restricted",...,resource="controller"} 2     <- templates are evaluated too
#   {decision="deny",mode="audit",policy_level="restricted",...,resource="pod"} 14
```

---

## Useful commands
```bash
kubectl get ns -L pod-security.kubernetes.io/enforce,pod-security.kubernetes.io/warn,pod-security.kubernetes.io/audit
kubectl label --dry-run=server --overwrite ns <ns> pod-security.kubernetes.io/enforce=restricted
kubectl label --dry-run=server --overwrite ns --all pod-security.kubernetes.io/enforce=baseline     # cluster-wide preview
```

## Cleanup
```bash
./cleanup.sh
```
