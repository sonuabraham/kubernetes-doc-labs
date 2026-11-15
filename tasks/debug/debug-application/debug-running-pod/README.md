# Debug Running Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/

> Runs on the default **minikube** cluster (8 CPUs, so the Pending example needs more replicas than the docs use).
> The docs' `kubectl debug -it …` sessions are run **non-interactively** here (`kubectl debug … -- <cmd>` + `kubectl logs -c <container>`,
> or `--attach=false` + `kubectl exec`). Add `-it` and drop the command to get the docs' interactive shell.
> Files (docs, **verbatim**): [nginx-with-request.yaml](nginx-with-request.yaml), [aggregate-ephemeralcontainers-edit.yaml](aggregate-ephemeralcontainers-edit.yaml),
> [debug-ephemeralcontainers.yaml](debug-ephemeralcontainers.yaml), [custom-profile.yaml](custom-profile.yaml).

## Key ideas (read first)

| Tool | When | Notes |
|---|---|---|
| `kubectl describe` / `get -o yaml` / events | always first | events are namespaced; `--all-namespaces` for everything |
| `kubectl logs [-c] [--previous]` | the app runs or ran | |
| `kubectl exec` | the image has the tools | |
| `kubectl debug <pod> --image=… --target=<ctr>` | **ephemeral container** in the *running* Pod: distroless, no shell | `--target` shares that container's PID namespace. It can't be removed afterwards. Needs RBAC on the `pods/ephemeralcontainers` subresource. |
| `kubectl debug <pod> --copy-to=…` | change the Pod: add a container, change the command (crash on start), swap images | **labels are dropped** (`--keep-labels=false`), so the copy gets no Service traffic |
| `kubectl debug node/<n>` | node problems | host namespaces + node fs at `/host`. Not privileged unless `--profile=sysadmin`. |
| `--profile` | security context of the debug container | `legacy` (default, deprecated), `general`, `baseline`, `restricted`, `netadmin`, `sysadmin`. `--custom` adds a partial container spec. |

---

## Step 0
```bash
cd tasks/debug/debug-application/debug-running-pod
```

## Lab 1 – describe, events, `-o yaml` (docs)
```bash
kubectl apply -f nginx-with-request.yaml
kubectl describe pod $(kubectl get pod -l app=nginx -o name | head -1) | sed -n '/^Containers:/,/^Conditions:/p'
#   State: Running   Ready: True   Restart Count: 0
#   Limits:   cpu: 500m  memory: 128Mi
#   Requests: cpu: 500m  memory: 128Mi              <- requests default to limits → QoS Guaranteed
kubectl get pod $(kubectl get pod -l app=nginx -o name | head -1) -o jsonpath='{.status.qosClass}'     # Guaranteed
```

## Lab 2 – Pending Pods (docs, scaled to fit an 8-CPU node)
```bash
kubectl scale deployment nginx-deployment --replicas=20
kubectl get pods -l app=nginx --no-headers | awk '{print $3}' | sort | uniq -c      # … 7 Pending …
PP=$(kubectl get pod -l app=nginx --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')
kubectl get events --field-selector involvedObject.name=$PP,reason=FailedScheduling -o jsonpath='{.items[-1].message}'
#   0/1 nodes are available: 1 Insufficient cpu. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
kubectl describe node minikube | grep -A4 'Allocated resources'
#   cpu   7950m (99%)   7100m (88%)
kubectl scale deployment nginx-deployment --replicas=2          # the docs' fix
kubectl get events --namespace=kube-system                      # events are per namespace
```

## Lab 3 – Who may add ephemeral containers? (docs RBAC)
```bash
kubectl create ns example-ns
kubectl create rolebinding alice-edit -n example-ns --clusterrole=edit --user=alice
kubectl run example -n example-ns --image=registry.k8s.io/pause:3.1 --restart=Never
kubectl auth can-i patch pods --subresource=ephemeralcontainers -n example-ns --as=alice     # no
kubectl debug example -n example-ns --image=busybox:1.28 --target=example --as=alice -- true
#   Error from server (Forbidden): pods "example" is forbidden: User "alice" cannot patch resource "pods/ephemeralcontainers" …
kubectl apply -f aggregate-ephemeralcontainers-edit.yaml       # aggregated into "edit" (and so into "admin")
kubectl auth can-i patch pods --subresource=ephemeralcontainers -n example-ns --as=alice     # yes
kubectl debug example -n example-ns --image=busybox:1.28 --target=example --as=alice -- true  # works
```
⚠️ `kubectl auth can-i update pods/ephemeralcontainers` answers **yes** even without the role. kubectl reads that as
"the pod *named* ephemeralcontainers". Use `--subresource=ephemeralcontainers`.
[debug-ephemeralcontainers.yaml](debug-ephemeralcontainers.yaml) is the docs' narrower alternative: bind it to an SRE group only.

## Lab 4 – Ephemeral container in a shell-less Pod (docs)
```bash
kubectl run ephemeral-demo --image=registry.k8s.io/pause:3.1 --restart=Never
kubectl exec -it ephemeral-demo -- sh
#   … exec: "sh": executable file not found in $PATH
kubectl debug ephemeral-demo --image=busybox:1.28 --target=ephemeral-demo --container=dbg --profile=general -- sh -c 'sleep 1; ps'
kubectl logs ephemeral-demo -c dbg
#   PID   USER     TIME  COMMAND
#     1 root      0:00 /pause       <- the target's processes
#    13 root      0:00 ps
kubectl debug ephemeral-demo --image=busybox:1.28 --container=dbg-notarget --profile=general -- sh -c 'sleep 1; ps'
kubectl logs ephemeral-demo -c dbg-notarget
#     1 root      0:00 ps           <- without --target: its own PID namespace
kubectl describe pod ephemeral-demo | sed -n '/^Ephemeral Containers:/,/^Conditions:/p' | grep -E '^  [a-z]'      # dbg, dbg-notarget
kubectl patch pod ephemeral-demo --subresource=ephemeralcontainers --type=json -p '[{"op":"remove","path":"/spec/ephemeralContainers/0"}]'
#   … spec.ephemeralContainers: Forbidden: existing ephemeral containers "dbg" may not be removed
```

## Lab 5 – Debug a copy of the Pod (docs, three variants)
```bash
# a) add a container + share processes
kubectl run myapp --image=busybox:1.28 --restart=Never -- sleep 1d
kubectl debug myapp --image=ubuntu --share-processes --copy-to=myapp-debug --container=debugger --attach=false -- sleep 1d
kubectl exec myapp-debug -c debugger -- ps -e -o pid,comm         # 1 pause, 7 sleep (myapp), 13 sleep (debugger) …
kubectl get pod myapp-debug -o json | jq -c '{share:.spec.shareProcessNamespace, ctrs:[.spec.containers[].name], labels:.metadata.labels}'
#   {"share":true,"ctrs":["myapp","debugger"],"labels":null}      <- labels dropped (--keep-labels=false)
kubectl delete pod myapp myapp-debug
# b) change the command of a crashing container
kubectl run --image=busybox:1.28 myapp -- false                    # Error / CrashLoopBackOff
kubectl debug myapp --copy-to=myapp-debug --container=myapp --attach=false -- sh -c 'sleep 1d'
kubectl exec myapp-debug -- sh -c 'false; echo "false exited with $?"'      # false exited with 1  <- reproduce by hand
kubectl delete pod myapp myapp-debug
# c) swap images
kubectl run myapp --image=busybox:1.28 --restart=Never -- sleep 1d
kubectl debug myapp --copy-to=myapp-debug --set-image=*=ubuntu
kubectl exec myapp-debug -- grep PRETTY /etc/os-release           # PRETTY_NAME="Ubuntu 26.04.1 LTS"
kubectl delete pod myapp myapp-debug
```
Without `--profile`, kubectl prints `--profile=legacy is deprecated … use "--profile=general"`.

## Lab 6 – A shell on the node (docs)
```bash
kubectl debug node/minikube --image=ubuntu --profile=general --attach=false -- sleep 300
ND=$(kubectl get pods -o name | grep node-debugger-minikube)
kubectl get $ND -o json | jq -c '{hostNetwork:.spec.hostNetwork, hostPID:.spec.hostPID, hostIPC:.spec.hostIPC, privileged:.spec.containers[0].securityContext.privileged, mount:.spec.containers[0].volumeMounts[0].mountPath}'
#   {"hostNetwork":true,"hostPID":true,"hostIPC":true,"privileged":null,"mount":"/host"}
kubectl exec $ND -- sh -c 'cat /host/etc/hostname; chroot /host true && echo chroot-ok; head -c1 /proc/1/environ || echo denied'
#   minikube    chroot-ok    denied       <- not privileged: some process info is off-limits
kubectl delete $ND
```

## Lab 7 – Capture traffic (docs `--profile=sysadmin` + tcpdump)
```bash
kubectl debug --profile=sysadmin node/minikube --image=ubuntu:latest --attach=false -- sh -c \
  'apt-get update -qq && apt-get install -y -qq tcpdump && echo TCPDUMP-READY && timeout 60 tcpdump -i any -n -c 4 "tcp port 80 and tcp[tcpflags] & tcp-syn != 0"'
# when the log shows TCPDUMP-READY, make some traffic to an nginx Pod:
kubectl run curl --image=busybox:1.36 --restart=Never -- wget -qO /dev/null http://$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].status.podIP}')/
kubectl logs $(kubectl get pods -o name | grep node-debugger)
```
```
05:38:40.089675 vethd4395db7 In  IP 10.244.0.75.55280 > 10.244.0.42.80: Flags [S], …     <- client Pod's veth
05:38:40.089753 vethd5d4e9a8 Out IP 10.244.0.75.55280 > 10.244.0.42.80: Flags [S], …     <- nginx Pod's veth
05:38:40.089775 vethd5d4e9a8 In  IP 10.244.0.42.80 > 10.244.0.75.55280: Flags [S.], …
05:38:40.089782 vethd4395db7 Out IP 10.244.0.42.80 > 10.244.0.75.55280: Flags [S.], …
```

## Lab 8 – Profiles (docs + Pod Security)
```bash
kubectl run myapp --image=busybox:1.28 --restart=Never -- sleep 1d
kubectl debug myapp --image=busybox:1.28 --target=myapp --profile=sysadmin --container=sysadm2 -- grep -E "CapPrm|CapEff" /proc/self/status
kubectl debug myapp --image=busybox:1.28 --target=myapp --profile=general  --container=general2 -- grep CapEff /proc/self/status
kubectl logs myapp -c sysadm2      # CapPrm/CapEff: 000001ffffffffff   (privileged: true)
kubectl logs myapp -c general2     # CapEff: 00000000a80c25fb          (default set + SYS_PTRACE)
kubectl debug myapp --image=busybox:1.28 --target=myapp --profile=general --custom=custom-profile.yaml --container=custom -- sh -c 'env | grep ENV_VAR'
kubectl get pod myapp -o jsonpath='{.spec.ephemeralContainers[?(@.name=="custom")].env}'              # ENV_VAR_1/2
kubectl get pod myapp -o jsonpath='{.spec.ephemeralContainers[?(@.name=="custom")].securityContext}'  # {"capabilities":{"add":["NET_ADMIN","SYS_TIME"]}}
```
Careful: in `kubectl debug … -- sh -c 'grep … /proc/$$/status'`, Kubernetes turns `$$` into a literal `$` (`$(VAR)` expansion
rules), so the docs' interactive `/proc/$$/status` only works inside a shell you attach to.

Ephemeral containers are checked by Pod Security too (docs note):
```bash
kubectl create ns dbg-restricted; kubectl label ns dbg-restricted pod-security.kubernetes.io/enforce=restricted
# create the restricted-compliant Pod "locked" (YAML below) in it, then:
kubectl debug -n dbg-restricted locked --image=busybox:1.36 --target=app --profile=general -- id
#   Error from server (Forbidden): … violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "debugger-…" …
kubectl debug -n dbg-restricted locked --image=busybox:1.36 --target=app --profile=restricted -- id
kubectl logs -n dbg-restricted locked -c <that debugger>          # uid=1000 gid=0(root) groups=0(root)
#   securityContext: {"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}
```
The restricted-compliant Pod used:
```yaml
apiVersion: v1
kind: Pod
metadata: {name: locked}
spec:
  securityContext: {runAsNonRoot: true, runAsUser: 1000, seccompProfile: {type: RuntimeDefault}}
  containers: [{name: app, image: registry.k8s.io/pause:3.9, securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}}]
```

## Useful commands
```bash
kubectl debug <pod> -it --image=busybox --target=<ctr> --profile=general
kubectl debug <pod> -it --copy-to=<pod>-debug --container=<ctr> -- sh
kubectl debug node/<node> -it --image=ubuntu --profile=sysadmin
kubectl get pod <pod> -o jsonpath='{.spec.ephemeralContainers[*].name}'
```

## Cleanup
```bash
./cleanup.sh
```
