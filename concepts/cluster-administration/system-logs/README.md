# System Logs – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/system-logs/

> No manifests on the page. The lab compares the real components' **text** logs with a throwaway scheduler logging **JSON** ([01-json-scheduler.yaml](01-json-scheduler.yaml)), and enables the kubelet's **log query** on a throwaway profile ([start-logquery-lab.sh](start-logquery-lab.sh), reuses `swap-lab`) to run the docs' `kubectl get --raw …/proxy/logs/?query=` commands.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **klog** | Kubernetes' logging library: `<severity I/W/E/F><MMDD hh:mm:ss.us> <pid> <file:line>] message`. |
| **Structured logging** (beta) | Messages as `"Message" key1="value" key2=...` with consistent keys (pod, node, err). |
| **Contextual logging** (beta, on) | Loggers carry names/values through call chains, e.g. `logger="UnhandledError"`. |
| **JSON format** | `--logging-format=json` (beta for some components): one JSON object per line (`ts`, `caller`, `msg`, `v`, keys). |
| **Verbosity** | `-v=N`: 0 always, 1–2 useful defaults, 3–4 debugging, 5+ trace. |
| **Location** | systemd services (kubelet, containerd) → journald. Static Pods (API server…) → container logs under `/var/log/pods`. |
| **Log query** (NodeLogQuery, GA) | Read node service logs via the API: `/api/v1/nodes/<n>/proxy/logs/?query=<service or file>&pattern=&tailLines=&sinceTime=…`. Needs kubelet `enableSystemLogQuery: true` (and `enableSystemLogHandler`). |

---

## Lab 1 – Structured, contextual text logs (real components)
```bash
kubectl logs -n kube-system -l component=kube-controller-manager --tail=50 | grep -m1 'logger='
#   E1112 07:53:20.347181  1 reflector.go:227] "Failed to watch" err="failed to list *v1.PartialObjectMetadata: ..." logger="UnhandledError" reflector="k8s.io/client-go/metadata/..."
#   ^sev ^date  ^time      ^pid ^file:line   ^message (quoted)  ^structured key=value pairs                 ^contextual logger name
```

## Lab 2 – JSON format and verbosity
```bash
cd concepts/cluster-administration/system-logs
kubectl apply -f 01-json-scheduler.yaml        # --logging-format=json --v=4
kubectl run p -n syslogs-lab --image=registry.k8s.io/pause:3.8 --overrides='{"spec":{"schedulerName":"json-scheduler"}}'
kubectl logs -n syslogs-lab deploy/json-scheduler | grep -m1 'Successfully bound' | jq -c .
#   {"ts":1794470470402.2139,"caller":"scheduler/schedule_one.go:483","msg":"Successfully bound pod to node",
#    "pod":{"name":"p","namespace":"syslogs-lab"},"v":2,"node":"minikube","evaluatedNodes":1,"feasibleNodes":1}
kubectl logs -n syslogs-lab deploy/json-scheduler | jq -r .v | sort | uniq -c
#   3 v=0   62 v=1   23 v=2   63 v=3   26 v=4       <- at -v=4 you see everything up to 4
```
The Pod reference became a nested object, which is easy for a log pipeline to index.

## Lab 3 – Node log query (docs commands)
```bash
kubectl get --raw "/api/v1/nodes/minikube/proxy/logs/?query=kubelet&tailLines=2"
#   main cluster: enableSystemLogQuery=false → the query is IGNORED and you get the /var/log directory listing (HTML)
./start-logquery-lab.sh                        # {"enableSystemLogQuery":true,"enableSystemLogHandler":true}
kubectl --context swap-lab get --raw "/api/v1/nodes/swap-lab/proxy/logs/?query=kubelet&tailLines=2"
#   Nov 12 08:01:48.868475 swap-lab kubelet[1583]: I1112 ... "Pod update broadcasted" podUID=... type="MODIFIED"
kubectl --context swap-lab get --raw "/api/v1/nodes/swap-lab/proxy/logs/?query=kubelet&pattern=error&tailLines=2"
#   ... E1112 08:01:40 pod_workers.go:1338] "Error syncing pod, skipping" err="failed to \"StartContainer\" for \"kube-proxy\" ...
kubectl --context swap-lab get --raw "/api/v1/nodes/swap-lab/proxy/logs/?query=/alternatives.log"
#   NotAcceptable: query: Invalid value: ["/alternatives.log"]: statat /alternatives.log: path escapes from parent
kubectl --context swap-lab get --raw "/api/v1/nodes/swap-lab/proxy/logs/?query=alternatives.log"
#   update-alternatives 2026-11-12 08:02:14: run with --set ip6tables /usr/sbin/ip6tables-nft     <- file names are relative to /var/log
```
Gotchas found: the docs' `query=/<file>` form (leading slash) is rejected, and options like `tailLines` aren't allowed with a file query (*"cannot specify file with options"*).

---

## Useful commands
```bash
kubectl logs -n kube-system -l component=kube-apiserver --tail=20
minikube ssh -- sudo journalctl -u kubelet -n 20 --no-pager
kubectl get --raw "/api/v1/nodes/<n>/proxy/logs/?query=kubelet&sinceTime=2026-11-12T08:00:00Z"
```

## Cleanup
```bash
./cleanup.sh
```
