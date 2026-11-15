# Auditing – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/

> Needs kube-apiserver flags, so it runs on a throwaway profile **`audit-lab`** (stop the default `minikube` first: inotify limit).
> [enable-audit.sh](enable-audit.sh) does the page's "Log backend" steps on the node: policy at `/etc/kubernetes/audit-policy.yaml`,
> log at `/var/log/kubernetes/audit/audit.log`, the docs' two `hostPath` volumes and mounts, and any extra flags.
> Files: [audit-policy.yaml](audit-policy.yaml), [audit-policy-minimal.yaml](audit-policy-minimal.yaml) (docs, **verbatim**).
> Not from the docs: [enable-audit.sh](enable-audit.sh), [audit-webhook-config.yaml](audit-webhook-config.yaml) (webhook backend kubeconfig),
> [audit-webhook-receiver.py](audit-webhook-receiver.py) (a toy webhook backend running on the node).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Stages** | `RequestReceived` → (`ResponseStarted`, only for long-running requests like watch) → `ResponseComplete` / `Panic`. One request can produce several events. |
| **Levels** | `None`, `Metadata` (who/what/when, no bodies), `Request` (+ request body), `RequestResponse` (+ response body). The **first matching rule** wins. |
| **Backends** | log (JSON lines, **blocking** by default) and webhook (**batch** by default, a kubeconfig-format target). Both can be on at once. |
| **Truncation** | Per backend, off by default. A truncated event loses its bodies and gets `audit.k8s.io/truncated: "true"`. |
| **Annotations** | Other components add to events: authorization decision, Pod Security (`pod-security.kubernetes.io/*`, where PSA's `audit` mode writes)… |

---

## Step 0 – Turn it on with the docs' policy
```bash
cd tasks/debug/debug-cluster/audit
minikube stop
./enable-audit.sh audit-policy.yaml
#   - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
#   - --audit-log-path=/var/log/kubernetes/audit/audit.log
#   API server ready
K="kubectl --context audit-lab"
log(){ minikube -p audit-lab ssh -- sudo cat /var/log/kubernetes/audit/audit.log; }
```

## Lab 1 – Which rule matched? (docs' policy)
```bash
$K run audit-demo --image=busybox:1.36 -- sleep 3600
$K create configmap demo-cm --from-literal=a=1
$K create configmap demo-cm -n kube-system --from-literal=a=1
$K create secret generic demo-secret --from-literal=password=s3cr3t
$K create deployment audit-dep --image=busybox:1.36 -- sleep 3600
$K get --raw /version
log | jq -c 'select(.user.username=="minikube-user") | {verb, res:.objectRef.resource, ns:.objectRef.namespace, level, req:(.requestObject!=null), resp:(.responseObject!=null)}' | sort | uniq -c
```
| Request | Level | Bodies | Docs rule |
|---|---|---|---|
| create/get/delete pods | `RequestResponse` | request + response | "Log pod changes at RequestResponse" |
| create configmap in kube-system | `Request` | request only | configmaps in kube-system |
| create configmap in default | `Metadata` | none | secrets + configmaps elsewhere |
| create secret | `Metadata` | none (**the password never reaches the log**) | same rule |
| create deployment | `Metadata` | none | `apps` isn't core/extensions, so the catch-all |
| GET `/version` | *(absent)* | | `None` for `/api*`, `/version` |
| GET `/readyz`, `/openapi/v2` | `Metadata` | | not matched by `/api*`, so the catch-all |
```bash
log | jq -r .stage | sort | uniq -c
#   343 ResponseComplete
#    77 ResponseStarted                  <- no RequestReceived at all: omitStages
```

## Lab 2 – Subresources and patch bodies (docs notes)
```bash
$K run audit-demo2 --image=busybox:1.36 -- sh -c 'echo hi; sleep 3600'; $K logs audit-demo2
$K patch pod audit-demo2 --type=json -p '[{"op":"add","path":"/metadata/labels/patched","value":"yes"}]'
log | jq -c 'select(.objectRef.name=="audit-demo2" and (.objectRef.subresource=="log" or .verb=="patch")) | {verb, sub:.objectRef.subresource, level, requestObject}'
```
```
{"verb":"patch","sub":"status","level":"Metadata","requestObject":null}      <- the kubelet's status updates: pods/status rule
{"verb":"get","sub":"log","level":"Metadata","requestObject":null}           <- pods/log rule ("pods" doesn't match subresources)
{"verb":"patch","sub":null,"level":"RequestResponse","requestObject":[{"op":"add","path":"/metadata/labels/patched","value":"yes"}]}   <- a JSON array, as the docs note
```
```bash
$K get --raw /metrics | grep -E '^apiserver_audit_(event_total|level_total)'
#   apiserver_audit_event_total 838
#   apiserver_audit_level_total{level="Metadata"} 468  …{level="None"} 19  …{level="Request"} 282  …{level="RequestResponse"} 61
```

## Lab 3 – Webhook backend + batching (docs flags)
```bash
./enable-audit.sh audit-policy-minimal.yaml --audit-webhook-batch-max-wait=5s
#   … - --audit-webhook-config-file=/etc/kubernetes/audit-webhook.yaml      (+ the toy receiver on 127.0.0.1:9880)
minikube -p audit-lab ssh -- "sudo grep batch_at /var/log/audit-webhook.jsonl"
#   {"batch_at": "09:35:56", "kind": "EventList", "events": 400}     <- capped by --audit-webhook-batch-max-size (default 400)
#   {"batch_at": "09:36:01", "kind": "EventList", "events": 258}     <- then every 5 s (--audit-webhook-batch-max-wait)
#   {"batch_at": "09:36:06", "kind": "EventList", "events": 143}
```
The log backend keeps writing at the same time (both backends active).

## Lab 4 – Truncation (docs flags)
```bash
./enable-audit.sh audit-policy.yaml --audit-webhook-batch-max-wait=5s \
  --audit-webhook-truncate-enabled=true --audit-webhook-truncate-max-event-size=4000
$K run big-pod --image=busybox:1.36 --annotations=blob=$(head -c 6000 /dev/zero | tr '\0' x) -- sleep 3600
```
| Backend | big-pod create event |
|---|---|
| webhook (truncate on) | `level: RequestResponse`, **no** request/response objects, `annotations: {"audit.k8s.io/truncated":"true", …}`, 929 bytes |
| log (truncate off) | full request + response, 15601 bytes |

The event also shows `"authorization.k8s.io/decision":"allow"` and `"pod-security.kubernetes.io/enforce-policy":"privileged:latest"`.
These annotations are added by other parts of the API server, which is how PSA's `audit` mode shows up.
With `Metadata`-level events, truncation had nothing to drop, and `apiserver_audit_error_total{plugin="truncate"}` counted the ones still too big.

## Step 5 – Back to the default cluster
```bash
./cleanup.sh       # minikube delete -p audit-lab
minikube start
```

## Useful commands
```bash
minikube -p audit-lab ssh -- "sudo tail -f /var/log/kubernetes/audit/audit.log" | jq -c '{user:.user.username, verb, uri:.requestURI, code:.responseStatus.code}'
kubectl get --raw /metrics | grep apiserver_audit
```

## Cleanup
```bash
./cleanup.sh
```
