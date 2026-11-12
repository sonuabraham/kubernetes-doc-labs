# Good Practices for Dynamic Admission Control – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/admission-webhooks-good-practices/

> The page has two shell commands (`kubectl get mutatingwebhookconfigurations` / `validatingwebhookconfigurations`) and a lot of advice. To try the advice, this lab runs a real webhook: [webhook.py](webhook.py) (stdlib Python, ~40 lines), deployed by [deploy-webhook.sh](deploy-webhook.sh) with a self-signed cert. Its endpoints: `/mutate` adds one label, `/validate` rejects `forbidden=true`, `/slow` does the same after a 5s sleep. [webhook-config.sh](webhook-config.sh) registers one configuration at a time with the page's recommended knobs.

## Key ideas (read first)

| Area | Good practice |
|---|---|
| **Inventory** | Know your webhooks: `kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations`. |
| **Prefer built-ins** | CRD schema validation/defaulting, ValidatingAdmissionPolicy / MutatingAdmissionPolicy (CEL, in-process) before webhooks. |
| **Latency and availability** | Fast handlers, small `timeoutSeconds` (default 10s, max 30), HA deployment behind a Service, no loops between controllers. |
| **Scope** | Narrow `rules` (resources, operations), `namespaceSelector`/`objectSelector` (exclude kube-system and the webhook's own namespace), **`matchConditions`** (CEL pre-filter), `apiVersions: ["*"]`. |
| **Mutations** | Patch only the fields you own, don't overwrite arrays, no side effects, no self-mutation, idempotent (`reinvocationPolicy`), don't depend on webhook order, don't touch immutable fields. |
| **Failure policy** | `Ignore` (fail open: availability) vs `Fail` (fail closed: safety). If you fail open, **validate the final state** some other way. |
| **Rollout** | Test in staging and across minor upgrades. Restrict who can edit webhook configurations (that's RBAC escalation, see `../../security/rbac-good-practices`). |

---

## Step 1
```bash
cd concepts/cluster-administration/admission-webhooks-good-practices
kubectl get mutatingwebhookconfigurations ; kubectl get validatingwebhookconfigurations      # No resources found (both)
./deploy-webhook.sh                      # namespace webhook-system, Deployment + Service lab-webhook (TLS)
kubectl create ns hooked ; kubectl label ns hooked webhook-lab=enabled ; kubectl create ns unhooked
```

## Lab 1 – Scope: namespaceSelector + matchConditions
```bash
./webhook-config.sh mutate
kubectl run p1 -n hooked   --image=registry.k8s.io/pause:3.8
kubectl run p2 -n unhooked --image=registry.k8s.io/pause:3.8
kubectl run p3 -n hooked   --image=registry.k8s.io/pause:3.8 --labels=skip-webhook=yes
#   hooked/p1   {"run":"p1","webhook.lab/seen":"true"}     <- mutated (one JSONPatch "add")
#   unhooked/p2 {"run":"p2"}                               <- namespaceSelector: never sent
#   hooked/p3   {"skip-webhook":"yes"}                     <- matchConditions (CEL) filtered it in the API server
kubectl logs -n webhook-system deploy/lab-webhook          # only p1 reached the webhook: "/mutate?timeout=5s CREATE hooked/p1"
```
Note the `?timeout=5s` the API server appends to the URL. The first version of `webhook.py` compared the raw path, matched nothing, and allowed everything without complaint, which is a good reason to test webhooks.

## Lab 2 – Validation
```bash
./webhook-config.sh validate
kubectl run bad -n hooked --image=registry.k8s.io/pause:3.8 --labels=forbidden=true
#   admission webhook "validate.lab.example.com" denied the request: label forbidden=true is not allowed (lab webhook)
```

## Lab 3 – Timeouts and failurePolicy (5s webhook, timeoutSeconds 2)
```bash
./webhook-config.sh slow-ignore
kubectl run slow1 -n hooked --image=registry.k8s.io/pause:3.8 --labels=forbidden=true
#   pod/slow1 created            took 2.22s        <- fail OPEN: the forbidden Pod got in!
./webhook-config.sh slow-fail
kubectl run slow2 -n hooked --image=registry.k8s.io/pause:3.8
#   Internal error occurred: failed calling webhook "slow-fail.lab.example.com": ... context deadline exceeded    took 2.22s   <- fail CLOSED
```
Every Pod creation in `hooked` now costs 2s or fails. A slow or down webhook is a cluster-wide outage for whatever it matches.

## Lab 4 – Fail open, but validate the final state
```bash
./webhook-config.sh slow-ignore
kubectl apply -f 01-final-state-vap.yaml        # the same rule as a ValidatingAdmissionPolicy (CEL, in-process)
kubectl run slow3 -n hooked --image=registry.k8s.io/pause:3.8 --labels=forbidden=true
#   ValidatingAdmissionPolicy 'no-forbidden-label' ... denied request: label forbidden=true is not allowed (final-state policy)
#   took 0.25s                                  <- rejected before the slow webhook was even called
```

---

## Useful commands
```bash
kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations -o custom-columns=NAME:.metadata.name,FAIL:.webhooks[*].failurePolicy,TIMEOUT:.webhooks[*].timeoutSeconds
kubectl get --raw /metrics | grep -E 'apiserver_admission_webhook_(admission_duration_seconds_count|rejection_count)' | head
```

## Cleanup
```bash
./cleanup.sh
```
