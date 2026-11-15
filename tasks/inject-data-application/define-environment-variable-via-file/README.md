# Define Environment Variable Values Using An Init Container – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-via-file/

> Runs on the default **minikube** cluster (`EnvFiles` is **beta and on** in 1.37), `default` namespace.
> Files: [envars-file-container.yaml](envars-file-container.yaml) (docs, **verbatim**). Not from the docs: [syntax-cases.yaml](syntax-cases.yaml)
> (one Pod per rule) and [syntax-matrix.py](syntax-matrix.py) (one Pod per syntax feature).
>
> **Found:** the rule "Spaces surrounding `=` are ignored" does **not** hold in 1.37: `VAL = 'value'` gives `couldn't parse env file`.
> All other rules on the page check out.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`valueFrom.fileKeyRef`** | `{volumeName, path, key, optional}`: the kubelet reads `key` from a file in an **emptyDir** volume when the container starts. |
| **Producer / consumer** | An init container (or sidecar) writes the file. The consumer container **doesn't mount** the volume: only the selected keys reach it. |
| **Syntax** | `KEY='value'` only. Single quotes are literal, multi-line values are allowed, and `#` lines are comments. No unquoted values, no double quotes, no expansion. |
| **Not a Secret** | emptyDir has none of a Secret's protections (encryption at rest, RBAC on the object, tmpfs) |

---

## Step 0
```bash
cd tasks/inject-data-application/define-environment-variable-via-file
kubectl get --raw /metrics | grep 'name="EnvFiles"'          # stage="BETA" 1
```

## Lab 1 – The docs' Pod
```bash
kubectl apply -f envars-file-container.yaml
kubectl get pods envfile-test-pod                            # Completed
kubectl logs envfile-test-pod -c use-envfile | grep DB_ADDRESS
#   DB_ADDRESS=address
kubectl logs envfile-test-pod -c use-envfile | grep -c REST_ENDPOINT
#   0                     <- in the file, but not referenced: not exposed
kubectl get pod envfile-test-pod -o json | jq -c '[.spec.containers[0].volumeMounts[].name]'
#   ["kube-api-access-…"] <- the consumer has no mount of the "config" volume
```

## Lab 2 – Errors and `optional` (not from the docs)
```bash
kubectl apply -f syntax-cases.yaml
for p in ok-multiline unquoted double-quoted missing-key missing-opt; do
  kubectl get pod envfile-$p -o jsonpath='{.status.phase} {.status.containerStatuses[0].state.waiting.message}'; echo; done
```
| Pod | File / reference | Result |
|---|---|---|
| ok-multiline | `# a comment` + `VAL='line1⏎line2 # not a comment'` | `[line1⏎line2 # not a comment]` |
| unquoted | `VAL=value` | `CreateContainerConfigError`: `couldn't parse env file` |
| double-quoted | `VAL="value"` | same |
| missing-key | key `MISSING`, `optional: false` | `environment variable key "MISSING" not found in file "/var/lib/kubelet/pods/…/config.env"` |
| missing-opt | key `MISSING`, `optional: true` | runs; variable simply unset (`[unset]`) |

## Lab 3 – Every syntax rule on its own (not from the docs)
```bash
python3 syntax-matrix.py | kubectl apply -f -
for n in plain spaces leading comment blank hash-inside multiline no-newline; do
  printf '%-12s %s\n' $n "$(kubectl logs ef-$n 2>/dev/null | tr '\n' '|' || true)$(kubectl get pod ef-$n -o jsonpath='{.status.containerStatuses[0].state.waiting.message}')"; done
```
| File content | Result | The page says |
|---|---|---|
| `VAL='value'` | ok | ✔ |
| `VAL = 'value'` | **`couldn't parse env file`** | "spaces surrounding `=` are ignored" ✘ |
| `   VAL='value'` | ok | leading spaces ignored ✔ |
| `# a comment` + line | ok | ✔ |
| blank lines around | ok | ✔ |
| `VAL='a # b'` | `[a # b]` | `#` inside quotes isn't a comment ✔ |
| `VAL='line1⏎line2'` | two lines | ✔ |
| no trailing newline | ok | |

## Cleanup
```bash
./cleanup.sh
```
