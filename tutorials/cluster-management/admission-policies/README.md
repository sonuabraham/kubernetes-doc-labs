# Explore Validating and Mutating Admission Policies – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/cluster-management/admission-policies/

> Runs on the default **minikube** (v1.37: both policy kinds are `admissionregistration.k8s.io/v1`). Files, **verbatim** from the docs:
> - the three code samples: [vap-min-replicas.yaml](vap-min-replicas.yaml), [default-pod-security-baseline.yaml](default-pod-security-baseline.yaml),
>   [default-pod-security-configurable.yaml](default-pod-security-configurable.yaml)
> - the page's inline YAML: [vap-binding.yaml](vap-binding.yaml), [map-binding-baseline.yaml](map-binding-baseline.yaml),
>   [another-example-ns.yaml](another-example-ns.yaml), [map-binding-configurable.yaml](map-binding-configurable.yaml),
>   [default-pod-security-standard-cm.yaml](default-pod-security-standard-cm.yaml)
>
> NOT from the docs: [vap-min-replicas-with-scale.yaml](vap-min-replicas-with-scale.yaml).
>
> **Found:**
> - **`kubectl scale` bypasses the replica policy.** "Create a Deployment and then scale it to 0 replicas using `kubectl scale`. What
>   happens?" It works: `deployment.apps/one scaled` → `0/0`, with `Deny` active. `kubectl scale` writes the `deployments/scale`
>   **subresource**, and the policy only matches `deployments`. The same change through `kubectl patch` is denied.
>   [vap-min-replicas-with-scale.yaml](vap-min-replicas-with-scale.yaml) adds `deployments/scale`. Then scaling to 1 is denied
>   (`failed expression: object.spec.replicas >= 2`). Scaling to 0 fails the expression with `no such key: replicas` (a Scale with 0
>   replicas omits the field), which `Deny` + failurePolicy `Fail` also rejects.
> - **"Existing resources aren't affected"** only means they aren't changed. Every later **update** of a Deployment with < 2 replicas is
>   denied, e.g. `kubectl set image deployment/one …` → `forbidden … failed expression: object.spec.replicas >= 2`.
> - **The docs' cleanup leaves the Deny policy active.** `kubectl delete validatingadmissionpolices/…` →
>   `error: the server doesn't have a resource type "validatingadmissionpolices"` (typo), and the binding it names
>   (`enforce-multiple-replicas-deployments`) doesn't exist; it's `…-binding`. Afterwards `default` still refuses 0/1-replica Deployments.
>   It also tries to delete `mutatingadmissionpolicybindings/default-pod-security-baseline`, which the tutorial already deleted (NotFound).
>   [cleanup.sh](cleanup.sh) is the corrected version.
> - **An empty parameter blocks all namespace creation.** The binding's comment says "if the ConfigMap is missing or empty, don't set a
>   default (but do allow namespace creation)". Missing works (no label is added). With `data.default: ""` the policy sets the label to
>   `""`, and every `kubectl create ns` fails: `metadata.labels[pod-security.kubernetes.io/enforce]: Invalid value: "": must be one of
>   privileged, baseline, restricted`. A typo in the ConfigMap would do the same.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Policy + Binding | the policy holds the CEL logic; the binding activates it and scopes it (`matchResources`), optionally with a `paramRef` |
| `validationActions` | `Deny`, `Warn`, `Audit`; `Deny` and `Warn` together are rejected by the API |
| MutatingAdmissionPolicy | `ApplyConfiguration` (server-side-apply style merge) or `JSONPatch`; here it **defaults** a label, it doesn't enforce it |
| `matchConditions` | CEL pre-filters (skip `kube-*` namespaces, skip if the label is already set) |
| `paramKind` + `paramRef` | configuration in a separate object (here a ConfigMap in kube-system); `parameterNotFoundAction: Allow` |
| Subresources | a rule for `deployments` doesn't cover `deployments/scale` (or `/status`) |

## Lab 1 – ValidatingAdmissionPolicy
```bash
kubectl apply --server-side -f vap-min-replicas.yaml
kubectl create deployment one --image=nginx --replicas=1      # works: the policy alone does nothing
kubectl apply -f vap-binding.yaml                             # Deny, namespace default
kubectl create deployment two --image=nginx --replicas=1
#   error: failed to create deployment: deployments.apps "two" is forbidden: ValidatingAdmissionPolicy 'enforce-multiple-replicas-deployments'
#   with binding 'enforce-multiple-replicas-deployments-binding' denied request: failed expression: object.spec.replicas >= 2
kubectl create deployment three --image=nginx --replicas=3
kubectl scale deployment three --replicas=0                   # deployment.apps/three scaled   <- NOT blocked (scale subresource)
kubectl patch deployment one -p '{"spec":{"replicas":0}}'     # denied (main resource)
kubectl set image deployment/one nginx=nginx:1.27             # denied: existing 1-or-0-replica Deployments can't be updated any more
```
NOT from the docs – close the gap, then try Warn:
```bash
kubectl apply --server-side --force-conflicts -f vap-min-replicas-with-scale.yaml
kubectl create deployment four --image=nginx --replicas=3
kubectl scale deployment four --replicas=1                    # The deployments "four" is invalid: … failed expression: object.spec.replicas >= 2
kubectl patch validatingadmissionpolicybinding enforce-multiple-replicas-deployments-binding --type=merge -p '{"spec":{"validationActions":["Warn"]}}'
kubectl scale deployment four --replicas=0
#   Warning: Validation failed for ValidatingAdmissionPolicy … expression 'object.spec.replicas >= 2' resulted in error: no such key: replicas
#   deployment.apps/four scaled
kubectl patch validatingadmissionpolicybinding enforce-multiple-replicas-deployments-binding --type=merge -p '{"spec":{"validationActions":["Deny","Warn"]}}'
#   … spec.validationActions: Invalid value: ["Deny","Warn"]: must not contain both Deny and Warn (repeating the same validation failure …)
kubectl patch validatingadmissionpolicybinding enforce-multiple-replicas-deployments-binding --type=merge -p '{"spec":{"validationActions":["Deny"]}}'
```

## Lab 2 – MutatingAdmissionPolicy (default a Pod Security label)
```bash
kubectl apply --server-side -f default-pod-security-baseline.yaml
kubectl apply -f map-binding-baseline.yaml
kubectl create ns example
kubectl describe ns example
#   Labels:  kubernetes.io/metadata.name=example
#            pod-security.kubernetes.io/enforce=baseline        <- added by the policy
kubectl apply --server-side -f another-example-ns.yaml        # namespace/another-example serverside-applied
kubectl get ns another-example --show-labels                  # … pod-security.kubernetes.io/enforce=privileged   (own value kept)
# NOT from the docs:
kubectl run priv --image=nginx --privileged -n another-example --dry-run=server   # pod/priv created (server dry run)
kubectl run priv --image=nginx --privileged -n example --dry-run=server           # Forbidden: violates PodSecurity "baseline:latest"
```

## Lab 3 – With a parameter resource
```bash
kubectl apply --server-side -f default-pod-security-configurable.yaml
kubectl apply -f default-pod-security-standard-cm.yaml        # ConfigMap FIRST (kube-system, default: baseline)
kubectl apply -f map-binding-configurable.yaml
kubectl delete mutatingadmissionpolicybindings/default-pod-security-baseline
kubectl create ns yet-another-example
kubectl describe ns yet-another-example                       # pod-security.kubernetes.io/enforce=baseline
kubectl --namespace kube-system edit configmap default-pod-security-standard     # default: restricted
#   non-interactive (NOT from the docs): kubectl -n kube-system patch configmap default-pod-security-standard -p '{"data":{"default":"restricted"}}'
kubectl create ns one-more-example
kubectl get ns one-more-example --show-labels                 # … pod-security.kubernetes.io/enforce=restricted   (no restart, no re-apply)
```
NOT from the docs – missing vs. empty parameter:
```bash
kubectl -n kube-system delete configmap default-pod-security-standard
kubectl create ns no-param-example                            # created, no pod-security label   (parameterNotFoundAction: Allow)
kubectl -n kube-system create configmap default-pod-security-standard --from-literal=default=
kubectl create ns empty-param-example
#   The Namespace "empty-param-example" is invalid: metadata.labels[pod-security.kubernetes.io/enforce]: Invalid value: "": must be one of privileged, baseline, restricted
```

## Cleanup
```bash
./cleanup.sh       # the docs' block with the two names fixed, plus this lab's test Deployments and Namespaces
```
