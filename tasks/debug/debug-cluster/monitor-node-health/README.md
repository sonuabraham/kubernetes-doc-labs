# Monitor Node Health – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/monitor-node-health/

> Runs Node Problem Detector (NPD) on the default **minikube** node.
> Files: [node-problem-detector.yaml](node-problem-detector.yaml), [node-problem-detector-configmap.yaml](node-problem-detector-configmap.yaml)
> (docs, **verbatim**). Not from the docs: [node-problem-detector-fixed.yaml](node-problem-detector-fixed.yaml) and
> [config/lab-kernel-monitor.json](config/lab-kernel-monitor.json) (the docs' "change the configuration files in `config/`" step).
>
> **Docs problems:** (1) `registry.k8s.io/node-problem-detector:v0.1` is a schema-1 image. containerd ≥ 2.1 refuses it
> (`ImagePullBackOff … manifest.v1+prettyjws is no longer supported`). (2) The manifests have no ServiceAccount/RBAC, `NODE_NAME`
> or monitor flags, all of which current NPD needs. The `-fixed` file adds them and uses v0.8.21.
> To stay off the host's real kernel log, the monitor watches a lab file (`/var/log/lab-kern.log`) that we write to.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **NPD** | A DaemonSet that watches node-level sources (kernel log, journald, custom scripts, health checks) and reports problems to the API. |
| **Problem daemons** | `SystemLogMonitor` (log rules), `SystemStatsMonitor` (metrics), `CustomPluginMonitor` (your scripts), `HealthChecker` (kubelet/runtime). |
| **Rules** | `temporary` → an **Event**. `permanent` → sets a **Node condition** (`KernelDeadlock=True`, …). |
| **Exporters** | Kubernetes (events + conditions), Prometheus (`:20257/metrics`), Stackdriver. |
| **What it doesn't do** | It doesn't taint, cordon or repair anything. Something else must act on the condition (an operator, a remediation controller, a human). |

---

## Step 0 – The docs' manifest
```bash
cd tasks/debug/debug-cluster/monitor-node-health
kubectl apply -f node-problem-detector.yaml
kubectl get pods -n kube-system -l k8s-app=node-problem-detector      # ImagePullBackOff
kubectl get events -n kube-system --field-selector reason=Failed | grep node-problem
#   Failed to pull image "registry.k8s.io/node-problem-detector:v0.1": … media type "application/vnd.docker.distribution.manifest.v1+prettyjws" is no longer supported since containerd v2.1 …
kubectl delete -f node-problem-detector.yaml
```

## Lab 1 – Overwrite the configuration with a ConfigMap (docs flow, fixed manifest)
```bash
minikube ssh -- "sudo touch /var/log/lab-kern.log"
kubectl create configmap node-problem-detector-config -n kube-system --from-file=config/      # the docs' command
kubectl apply -f node-problem-detector-fixed.yaml
kubectl logs -n kube-system -l k8s-app=node-problem-detector | tail -5
#   Use log watcher of plugin "filelog"
#   K8s exporter started.   Prometheus exporter started.
#   Start log monitor /config/lab-kernel-monitor.json
#   Initialize condition generated: [{Type:KernelDeadlock Status:False …
kubectl get node minikube -o json | jq -c '.status.conditions[]|select(.type=="KernelDeadlock")|{type,status,reason}'
#   {"type":"KernelDeadlock","status":"False","reason":"KernelHasNoDeadlock"}       <- a new node condition
```

## Lab 2 – Make "the kernel" report problems
```bash
minikube ssh -- 'TS=$(date "+%b %e %H:%M:%S")
  echo "$TS minikube kernel: [12345.678901] Killed process 4242 (memhog) total-vm:204800kB, anon-rss:102400kB, file-rss:0kB, shmem-rss:0kB" | sudo tee -a /var/log/lab-kern.log
  echo "$TS minikube kernel: [12346.000001] task docker:7 blocked for more than 300 seconds." | sudo tee -a /var/log/lab-kern.log'
kubectl get node minikube -o json | jq -c '.status.conditions[]|select(.type=="KernelDeadlock")|{status,reason,message}'
#   {"status":"True","reason":"DockerHung","message":"task docker:7 blocked for more than 300 seconds."}     <- permanent rule
kubectl get events -A --field-selector involvedObject.kind=Node | grep -E 'OOMKilling|DockerHung'
#   Warning  OOMKilling  kernel-monitor  Killed process 4242 (memhog) total-vm:204800kB, …                      <- temporary rule = event
#   Warning  DockerHung  kernel-monitor  Node condition KernelDeadlock is now: True, reason: DockerHung, …
minikube ssh -- "curl -s localhost:20257/metrics | grep -E '^problem_(counter|gauge)'"
#   problem_counter{reason="DockerHung"} 1
#   problem_counter{reason="OOMKilling"} 1
#   problem_gauge{reason="DockerHung",type="KernelDeadlock"} 1                                                  <- Prometheus exporter
```

## Lab 3 – What a condition does and doesn't do (not from the docs)
```bash
kubectl run sched-test --image=busybox:1.36 --restart=Never -- true
kubectl get pod sched-test -o wide         # Completed on minikube - KernelDeadlock=True doesn't block scheduling
kubectl get node minikube -o jsonpath='{.spec.taints}'        # (none)
kubectl delete -f node-problem-detector-fixed.yaml
kubectl get node minikube -o json | jq -c '.status.conditions[]|select(.type=="KernelDeadlock")|{status,reason}'
#   {"status":"True","reason":"DockerHung"}        <- the condition OUTLIVES NPD; nobody resets it
```
[cleanup.sh](cleanup.sh) removes it with a JSON patch on `nodes/status`.

## Useful commands
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,CONDITIONS:.status.conditions[*].type
kubectl describe node <node> | sed -n '/^Conditions:/,/^Addresses:/p'
kubectl get events -A --field-selector source=kernel-monitor
```

## Cleanup
```bash
./cleanup.sh
```
