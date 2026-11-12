# Guide for Running Windows Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/windows/user-guide/

> ⚠️ **minikube can't run Windows nodes.** The lab uses two API-only Windows nodes from [../fake-windows-nodes.sh](../fake-windows-nodes.sh): `win-2022` (`windows-build` 10.0.20348) and `win-2025` (10.0.26100). The scheduler, taints, RuntimeClass admission and Services all behave for real. Pods bound to the fake nodes stay `Pending` forever because no kubelet runs them.
>
> The docs' manifests are **verbatim**:
> - [win-webserver.yaml](win-webserver.yaml): NodePort Service + 2-replica PowerShell web server, `nodeSelector: kubernetes.io/os: windows`.
> - [toleration-excerpt.yaml](toleration-excerpt.yaml): nodeSelector with `windows-build` plus the `os=windows` toleration.
> - [runtimeClasses.yml](runtimeClasses.yml): RuntimeClass `windows-2019`.
> - [iis-2019.yaml](iis-2019.yaml): IIS Deployment using that RuntimeClass + LoadBalancer Service.
>
> Added for the lab:
> - [00-linux-app.yaml](00-linux-app.yaml): a "legacy" Linux Deployment with no selector.
> - [01-win-webserver-tolerating.yaml](01-win-webserver-tolerating.yaml): generated = win-webserver + the excerpt.
> - [02-handler-and-dollar.yaml](02-handler-and-dollar.yaml): two side experiments on the real node.
> - [reap.sh](reap.sh): force-deletes terminating Pods on the fake nodes (the missing kubelet's job).

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Same workflow** | Deployments, Services and kubectl work as on Linux. A Windows node is just another node with `kubernetes.io/os=windows`. |
| **Networking caveat** | A Windows **host** can't reach Service IPs of Pods scheduled on it. Only Windows **Pods** can reach Service IPs. |
| **Logs** | Windows apps log to ETW/Event Log, not stdout. **LogMonitor** (Microsoft) forwards them to stdout for `kubectl logs`. |
| **Identity** | `windowsOptions.runAsUserName` (container user) and **gMSA** (Active Directory identity). See `../../security/windows-security`. |
| **`spec.os.name`** | Set it on every Pod. The **scheduler ignores it**, so it doesn't place Pods. |
| **nodeSelector `kubernetes.io/os: windows`** | Best practice for Windows Pods. Without it, Pods can land on Linux nodes. |
| **Taint `os=windows:NoSchedule`** | Set on Windows nodes (`--register-with-taints`) so that **existing Linux workloads** without selectors can't land there. Windows Pods then need **both** the nodeSelector and the toleration. |
| **`node.kubernetes.io/windows-build`** | Automatic node label, e.g. `10.0.20348` (Server 2022) or `10.0.26100` (Server 2025). Use it when you run several Windows versions, since image and host builds must match. |
| **RuntimeClass `scheduling`** | Bundles the nodeSelector and tolerations. Pods just set `runtimeClassName`, and admission merges the rest in. |

---

## Step 1 – A mixed cluster
```bash
cd concepts/windows/user-guide
../fake-windows-nodes.sh up
kubectl create ns win-guide
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build
#   minikube   linux
#   win-2022   windows   10.0.20348
#   win-2025   windows   10.0.26100
```

## Lab 1 – Deploy the docs' web server
```bash
kubectl apply -f win-webserver.yaml -n win-guide
kubectl get pods -n win-guide -o wide
#   win-webserver-5b58699bf9-27c56   Pending   win-2025     <- nodeSelector os=windows: only Windows nodes
#   win-webserver-5b58699bf9-cc952   Pending   win-2022        (Pending = the fake nodes don't run anything)
kubectl get svc win-webserver -n win-guide                 # NodePort 80:31491/TCP - endpoints stay empty until Pods are Ready
```
On a real cluster, the page's verification list applies: curl Pod IPs from the control plane, Pod-to-Pod ping, the Service IP from Pods, DNS names, NodePort from outside, and outbound traffic from inside.

**The `$$` in the command.** The docs write `$$listener`. Kubernetes expands `$(VAR)` in `command`/`args`, and `$$` is its escape for a literal `$`:
```bash
kubectl apply -f 02-handler-and-dollar.yaml
kubectl logs dollar -n win-guide
#   GREETING=hello x=$x literal=$(GREETING) unknown=$(NOPE)
#   (in the YAML: $(GREETING) -> expanded,  $$x -> $x,  $$(GREETING) -> literal,  unknown $(NOPE) -> left as is)
```
So PowerShell receives `$listener`.

## Lab 2 – Why the taint: legacy Linux workloads
```bash
kubectl apply -f 00-linux-app.yaml
kubectl get pods -n win-guide -l app=linux-app --no-headers -o custom-columns=NODE:.spec.nodeName | sort | uniq -c
#   2 minikube
#   2 win-2022      <- a Linux image on a Windows node: it could never start there
#   2 win-2025
```
The fix the page recommends is to leave the Linux workloads alone and taint the Windows nodes:
```bash
kubectl taint node win-2022 win-2025 os=windows:NoSchedule        # what --register-with-taints='os=windows:NoSchedule' does
kubectl rollout restart deploy linux-app -n win-guide ; ./reap.sh     # reap = let the fake nodes "finish" the old Pods
kubectl get pods -n win-guide -l app=linux-app --no-headers -o custom-columns=NODE:.spec.nodeName | sort | uniq -c
#   6 minikube
```
The taint keeps the docs' web server out too, because it has a nodeSelector but **no toleration**:
```bash
kubectl delete deploy win-webserver -n win-guide ; ./reap.sh ; kubectl apply -f win-webserver.yaml -n win-guide
kubectl get events -n win-guide --field-selector reason=FailedScheduling -o custom-columns=MSG:.message --no-headers | tail -1
#   0/3 nodes are available: 1 node(s) didn't match Pod's node affinity/selector, 2 node(s) had untolerated taint(s).
```
(A `rollout restart` of win-webserver gets stuck here: new Pods on fake nodes never become Ready, so the old ReplicaSet is never scaled down. That's why the lab deletes and re-creates it.)

## Lab 3 – nodeSelector + toleration, pinned to one Windows version
```bash
kubectl apply -f 01-win-webserver-tolerating.yaml -n win-guide       # docs Pod template + toleration-excerpt.yaml
kubectl get pods -n win-guide -l 'app in (win-webserver,win-webserver-2022)' -o wide
#   win-webserver-2022-68864f7c7c-jk9f2   Pending   win-2022     <- tolerates the taint, windows-build=10.0.20348 only
#   win-webserver-2022-68864f7c7c-r8d2q   Pending   win-2022
#   win-webserver-5b58699bf9-9p84b        Pending   <none>       <- the docs' original: unschedulable
#   win-webserver-5b58699bf9-g7lgc        Pending   <none>
```

## Lab 4 – RuntimeClass bundles it
```bash
kubectl create -f runtimeClasses.yml
kubectl apply -f iis-2019.yaml -n win-guide
P=$(kubectl get pods -n win-guide -l app=iis-2019 -o name | head -1)
kubectl get $P -n win-guide -o wide                                  # Pending on win-2022
kubectl get $P -n win-guide -o jsonpath='{.spec.nodeSelector}{"\n"}{.spec.tolerations[2]}{"\n"}'
#   {"kubernetes.io/arch":"amd64","kubernetes.io/os":"windows","node.kubernetes.io/windows-build":"10.0.20348"}
#   {"effect":"NoSchedule","key":"os","operator":"Equal","value":"windows"}      <- merged in by RuntimeClass admission
kubectl get svc iis -n win-guide                                     # LoadBalancer <pending> (run `minikube tunnel` for an IP)
```
Admission refuses conflicts and unknown classes:
```bash
kubectl run conflict -n win-guide --image=busybox:1.36 --dry-run=server \
  --overrides='{"spec":{"runtimeClassName":"windows-2019","nodeSelector":{"kubernetes.io/os":"linux"}}}'
#   forbidden: conflict: runtimeClass.scheduling.nodeSelector[kubernetes.io/os] = windows; pod.spec.nodeSelector[kubernetes.io/os] = linux
kubectl run nohandler -n win-guide --image=busybox:1.36 --dry-run=server --overrides='{"spec":{"runtimeClassName":"does-not-exist"}}'
#   forbidden: pod rejected: RuntimeClass "does-not-exist" not found
```
The `handler` must exist in the node's containerd config. The docs' `example-container-runtime-handler` is a placeholder. `02-handler-and-dollar.yaml` tries it on the real node:
```bash
kubectl get events -n win-guide --field-selector involvedObject.name=handler-test -o custom-columns=MSG:.message --no-headers
#   Failed to create pod sandbox: ... no runtime for "example-container-runtime-handler" is configured
```

## Notes on the docs' examples
- `win-webserver` and `iis-2019` use **ltsc2019** images (build **10.0.17763**, Windows Server 2019). Per `../intro`, v1.37 supports only Server 2022/2025 nodes, and process isolation needs matching builds. Use `ltsc2022` images on 2022 nodes.
- The RuntimeClass is **named `windows-2019`** but selects `windows-build: 10.0.20348` (**Server 2022**), so the 2019 IIS image it's paired with wouldn't match that host either.
- Neither example sets `spec.os.name: windows`, although the page says you should.

---

## Useful commands
```bash
kubectl get nodes -L kubernetes.io/os,node.kubernetes.io/windows-build
kubectl taint node <win-node> os=windows:NoSchedule
kubectl get runtimeclass ; kubectl get pod <p> -o jsonpath='{.spec.nodeSelector} {.spec.tolerations}'
```

## Cleanup
```bash
./cleanup.sh        # RuntimeClasses, namespace win-guide (force), fake Windows nodes
```
