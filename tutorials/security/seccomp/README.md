# Restrict a Container's Syscalls with seccomp – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/security/seccomp/

> The page uses a **kind** cluster ([kind.yaml](kind.yaml) mounts `./profiles` at `/var/lib/kubelet/seccomp/profiles`). kind isn't installed
> here, so the profiles are copied onto the **default minikube** node with `minikube cp` (same path, same effect), and
> `docker exec -it kind-control-plane curl …` becomes `minikube ssh -- curl …`. The `--seccomp-default` part runs on a throwaway profile
> `seccomp-lab`.
> Files, **verbatim**: [profiles/](profiles/) (`audit.json`, `violation.json`, `fine-grained.json`), [kind.yaml](kind.yaml) (reference),
> `default-pod.yaml`, `audit-pod.yaml`, `violation-pod.yaml`, `fine-pod.yaml` (`examples/pods/security/seccomp/ga/`).
> NOT from the docs: [fine-grained-fixed.json](fine-grained-fixed.json), [fine-pod-fixed.yaml](fine-pod-fixed.yaml).
>
> **Found:**
> - **`fine-pod` doesn't start any more.** Status `RunContainerError`, and the container log is
>   `reopen exec fifo: get safe /proc/thread-self/fd handle: fstat fsmount:fscontext:proc: operation not permitted`.
>   runc **1.4.3** installs the filter (late, because `allowPrivilegeEscalation: false` sets no_new_privs) and then still needs a few
>   syscalls before `execve`. Using the page's own method (the same allow-list with `defaultAction: SCMP_ACT_LOG`), only `runc:[2:INIT]`
>   logged anything: syscalls **5 `fstat`, 332 `statx`, 437 `openat2`**. `http-echo` itself needed nothing outside the list.
>   [fine-grained-fixed.json](fine-grained-fixed.json) = the docs list + those three. It runs, answers, and logs **0** lines.
> - `violation-pod` shows `RunContainerError` (`StartError`, `cannot start a stopped process`, exit code 128), not `CrashLoopBackOff`.
>   With every syscall denied, the process never gets to `execve`.
> - The audit lines aren't readable in `/var/log/syslog` (`-rw-r----- syslog adm`) as a normal user; `journalctl -k` shows them. They show
>   `uid=65532` (`http-echo:1.0` runs as nonroot) and `subj=runc` (the host's AppArmor runc profile).
> - The first `curl` straight after `kubectl expose` can fail with exit 7 (connection refused) while kube-proxy programs the NodePort; retry.
> - `--seccomp-default=true` works (`Seccomp: 2`, RuntimeDefault in the runtime spec), but the kubelet's `/configz` still reports
>   `"seccompDefault": false` when it's set as a **flag**. Check the container, not configz.
> - The minikube node has no `jq` (the docs' `crictl inspect … | jq` check); `python3` is there.
> - `http-echo:1.0` is distroless: `kubectl exec … cat` doesn't work in these Pods.

## Key ideas (read first)

| `seccompProfile.type` | Meaning |
|---|---|
| `RuntimeDefault` | containerd's default filter (`defaultAction: SCMP_ACT_ERRNO` + ~14 allow rules covering the usual syscalls) |
| `Localhost` + `localhostProfile: profiles/x.json` | a JSON file **relative to** `<kubelet root>/seccomp/` on the node |
| `Unconfined` | no filter: the default unless the kubelet runs with `--seccomp-default` |
| `SCMP_ACT_LOG` | allow, but write an audit record (`type=1326 … syscall=N`) to the kernel log |
| `SCMP_ACT_ERRNO` | deny with an error (EPERM) |
| `privileged: true` | always unconfined, no profile applies |

## Lab 1 – Profiles on the node, RuntimeDefault
```bash
cd tutorials/security/seccomp
ls profiles                                                    # audit.json  fine-grained.json  violation.json
minikube ssh -- 'sudo mkdir -p /var/lib/kubelet/seccomp/profiles'
for f in profiles/*.json; do minikube cp $f /var/lib/kubelet/seccomp/$f; done
minikube ssh -- 'sudo ls /var/lib/kubelet/seccomp/profiles'   # audit.json  fine-grained.json  violation.json

kubectl apply -f default-pod.yaml
kubectl get pod default-pod                                    # 1/1 Running
kubectl delete pod default-pod --wait --now
```

## Lab 2 – Audit profile (log every syscall)
```bash
kubectl apply -f audit-pod.yaml
kubectl get pod audit-pod                                      # 1/1 Running
kubectl expose pod audit-pod --type NodePort --port 5678
kubectl get service audit-pod                                  # 5678:31765/TCP
minikube ssh -- curl localhost:31765                           # just made some syscalls!   (retry if exit 7)
journalctl -k -f | grep http-echo                              # (docs: tail -f /var/log/syslog | grep 'http-echo')
#   kernel: audit: type=1326 … uid=65532 gid=65532 … subj=runc … comm="http-echo" exe="/http-echo" sig=0 arch=c000003e syscall=288 … code=0x7ffc0000
#   per request: syscall 288 accept4, 202 futex, 35 nanosleep, 233 epoll_ctl, 54 setsockopt, 51 getsockname
kubectl delete service audit-pod --wait
kubectl delete pod audit-pod --wait --now
```

## Lab 3 – Violation profile (deny everything)
```bash
kubectl apply -f violation-pod.yaml
kubectl get pod violation-pod                                  # 0/1   RunContainerError   2 (1s ago)
kubectl describe pod violation-pod | grep -E 'Reason|Message|Exit Code'
#   Reason: StartError   Message: failed to start containerd task "…": cannot start a stopped process   Exit Code: 128
kubectl delete pod violation-pod --wait --now
```

## Lab 4 – Fine-grained profile
```bash
kubectl apply -f fine-pod.yaml
kubectl get pod fine-pod                                       # 0/1   RunContainerError   <- docs expect Running
kubectl logs fine-pod
#   reopen exec fifo: get safe /proc/thread-self/fd handle: fstat fsmount:fscontext:proc: operation not permitted
kubectl delete pod fine-pod --now
```
NOT from the docs – find what's missing with the page's own audit method, then fix:
```bash
python3 -c 'import json; p=json.load(open("profiles/fine-grained.json")); p["defaultAction"]="SCMP_ACT_LOG"; print(json.dumps(p))' > /tmp/fine-grained-log.json
minikube cp /tmp/fine-grained-log.json /var/lib/kubelet/seccomp/profiles/fine-grained-log.json
sed 's/fine-grained.json/fine-grained-log.json/; s/name: fine-pod/name: fine-log-pod/' fine-pod.yaml | kubectl apply -f -
journalctl -k | grep -E 'comm="(http-echo|runc:\[2:INIT\])"' | grep -o 'comm="[^"]*".*syscall=[0-9]*' | sed -E 's/ exe=.*syscall=/ syscall=/' | sort | uniq -c
#   1 comm="runc:[2:INIT]" syscall=332     statx
#   2 comm="runc:[2:INIT]" syscall=437     openat2
#   1 comm="runc:[2:INIT]" syscall=5       fstat          <- nothing from http-echo, even after a curl
kubectl delete pod fine-log-pod --now

minikube cp fine-grained-fixed.json /var/lib/kubelet/seccomp/profiles/fine-grained-fixed.json
kubectl apply -f fine-pod-fixed.yaml
kubectl get pod fine-pod-fixed                                 # 1/1 Running
kubectl expose pod fine-pod-fixed --type NodePort --port 5678
minikube ssh -- curl localhost:<nodePort>                      # just made some syscalls!
journalctl -k --since -1min | grep -c http-echo                # 0   <- nothing denied, nothing logged
kubectl delete service fine-pod-fixed --wait; kubectl delete pod fine-pod-fixed --wait --now
```

## Lab 5 – RuntimeDefault for everything (`--seccomp-default`)
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | python3 -c 'import json,sys; print(json.load(sys.stdin)["kubeletconfig"]["seccompDefault"])'   # False
kubectl run --rm -i --restart=Never --image=alpine alpine -- grep Seccomp /proc/1/status     # Seccomp: 0   <- unconfined

minikube stop
minikube start -p seccomp-lab --kubernetes-version v1.37.0 --extra-config=kubelet.seccomp-default=true   # (docs: kind config with kubeletExtraArgs)
minikube -p seccomp-lab ssh -- 'ps -o args= -C kubelet' | tr ' ' '\n' | grep seccomp      # --seccomp-default=true
kubectl get --raw /api/v1/nodes/seccomp-lab/proxy/configz | python3 -c '…seccompDefault…'   # False   <- misleading, see "Found"
kubectl run alpine --restart=Never --image=alpine -- sleep 300           # (right after start: "serviceaccount default not found" → wait a few s)
kubectl exec alpine -- grep Seccomp /proc/1/status                       # Seccomp: 2   Seccomp_filters: 1   <- filtered
kubectl get pod alpine -o jsonpath='{.spec.securityContext.seccompProfile}'   # (empty – the spec isn't changed)
minikube -p seccomp-lab ssh -- "sudo crictl inspect \$(sudo crictl ps --name=alpine -q) | python3 -c 'import json,sys; s=json.load(sys.stdin)[\"info\"][\"runtimeSpec\"][\"linux\"][\"seccomp\"]; print(s[\"defaultAction\"], s[\"architectures\"], len(s[\"syscalls\"]))'"
#   SCMP_ACT_ERRNO ['SCMP_ARCH_X86_64', 'SCMP_ARCH_X86', 'SCMP_ARCH_X32'] 14
minikube delete -p seccomp-lab; minikube start
```

## Cleanup
Docs: `kind delete cluster`. Here:
```bash
./cleanup.sh        # Pods/Services, /var/lib/kubelet/seccomp/profiles on the node, profile seccomp-lab
```
