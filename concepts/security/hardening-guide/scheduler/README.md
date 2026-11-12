# Hardening Guide – Scheduler Configuration – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/security/hardening-guide/scheduler/

> The docs' KubeSchedulerConfiguration is **verbatim** in [02-kubeschedulerconfig-disable-plugins.yaml](02-kubeschedulerconfig-disable-plugins.yaml). [03-my-scheduler.yaml](03-my-scheduler.yaml) runs it as a **second scheduler** (minimal changes, explained there). [00-debug-reader.yaml](00-debug-reader.yaml) is an identity for probing the scheduler's debug endpoints.

## Key ideas (read first)

| Area | Recommendation from the page |
|---|---|
| **Why it matters** | A misconfigured scheduler can steer Pods onto chosen nodes, starve or evict neighbours, or feed autoscaler "Yo-Yo" attacks. |
| **AuthN/AuthZ flags** | `--authentication-kubeconfig` / `--authorization-kubeconfig` (protected files), `authentication-tolerate-lookup-failure=false`, `authentication-skip-lookup=false`, keep `authorization-always-allow-paths` to health endpoints, don't set `requestheader-client-ca-file`. |
| **Profiling** | Disable (`enableProfiling: false` in config; `--profiling` is deprecated): pprof leaks internals and is a DoS vector. |
| **Network** | `bind-address=127.0.0.1`, `permit-address-sharing=false`, `permit-port-sharing=false`, explicit `tls-cipher-suites`. |
| **Custom schedulers** | Scrutinise plugins at `queueSort` (exactly one allowed), `preFilter`/`filter` (can make every node unschedulable, or none), `permit` (can hold or delay binding). Disable defaults you don't want, as the docs' config does. |

---

## Lab 1 – Review the default scheduler
```bash
cd concepts/security/hardening-guide/scheduler
kubectl get pod -n kube-system -l component=kube-scheduler -o json | jq -r '.items[0].spec.containers[0].command[]'
#   --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
#   --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
#   --bind-address=127.0.0.1               <- good: not reachable from outside the node
#   --kubeconfig=/etc/kubernetes/scheduler.conf
#   --leader-elect=false
minikube ssh -- "sudo ss -ltnp | grep 10259"          # 127.0.0.1:10259 only
minikube ssh -- "for p in /healthz /metrics /debug/pprof/ /configz; do curl -sk -o /dev/null -w \"\$p %{http_code}\n\" https://127.0.0.1:10259\$p; done"
#   /healthz 200   (always-allow path)    /metrics 403   /debug/pprof/ 403   /configz 403    <- anonymous
```

## Lab 2 – Profiling is on by default
```bash
kubectl apply -f 00-debug-reader.yaml
T=$(kubectl create token debug-reader -n sched-harden)
minikube ssh -- "for p in /metrics /debug/pprof/ /configz; do curl -sk -o /dev/null -w \"\$p %{http_code}\n\" -H 'Authorization: Bearer $T' https://127.0.0.1:10259\$p; done"
#   /metrics 200   /debug/pprof/ 200   /configz 200        <- anyone granted the non-resource URL can profile the scheduler
```
Set `enableProfiling: false` (KubeSchedulerConfiguration `DebuggingConfiguration`) and grant `/debug/*` to nobody.

## Lab 3 – What disabling filter plugins really does
The docs' profile **as written** doesn't start:
```
"command failed" err="initializing profiles: creating profile for scheduler name my-scheduler:
 only one queue sort plugin required for profile with scheduler name \"my-scheduler\", but got 0"
```
Disabling `queueSort: "*"` only makes sense if your own queueSort plugin is enabled in its place. [03-my-scheduler.yaml](03-my-scheduler.yaml) keeps the default queueSort and disables **filter** and **permit** as in the docs:
```bash
kubectl apply -f 03-my-scheduler.yaml ; kubectl rollout status deploy/my-scheduler -n sched-harden
kubectl apply -n sched-harden -f 04-test-pods.yaml
kubectl get pods -n sched-harden -o wide | grep -v my-scheduler
#   same-but-default-scheduler   Pending        <none>      <- default scheduler: no node matches the selector
#   too-much-cpu                 OutOfcpu       minikube    <- my-scheduler bound it anyway (no NodeResourcesFit filter)
#   wrong-node-selector          NodeAffinity   minikube    <- ... and ignored nodeSelector (no NodeAffinity filter)
kubectl get pod too-much-cpu -n sched-harden -o jsonpath='{.status.message}'
#   Pod was rejected: Node didn't have enough resource: cpu, requested: 64000, used: 950, capacity: 8000
```
Without filters the scheduler happily binds anything anywhere. The **kubelet's admission** (it re-checks node affinity, resources, taints) is the backstop, and the Pods end up `Failed` instead of `Pending`. A scheduler without filters can also put Pods on nodes they must not reach (tainted, dedicated tenant nodes) wherever the kubelet doesn't re-check, for example tolerations against `NoSchedule` taints. Review custom scheduler plugins like any privileged code.

---

## Useful commands
```bash
kubectl get pods -A -o custom-columns=NAME:.metadata.name,SCHEDULER:.spec.schedulerName | grep -v default-scheduler
kubectl get events --field-selector reason=Scheduled -o custom-columns=FROM:.source.component,MSG:.message
```

## Cleanup
```bash
./cleanup.sh
```
