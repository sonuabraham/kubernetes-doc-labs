# Debugging Kubernetes Nodes With Kubectl – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/kubectl-node-debug/

> Runs on the default **minikube** node. The docs' interactive `kubectl debug node/mynode -it --image=ubuntu` works as is. Below, the
> sessions are started with `--attach=false -- sleep 300` and inspected with `kubectl exec`, so the output can be shown.
> The general `kubectl debug` tour (ephemeral containers, copies, tcpdump) is in [debug-running-pod](../../debug-application/debug-running-pod/).
>
> **Differences from the page, measured:** (1) "`chroot /host` will fail" is not true here. It works with every profile, because
> `CAP_SYS_CHROOT` is in the default capability set. What fails without privileges is reading other processes' `environ` and `nsenter`
> into host namespaces. (2) None of the listed `/host/var/log/*.log` files exist on this systemd-based node. Use `journalctl` via chroot.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **What it creates** | A Pod `node-debugger-<node>-<x>` pinned to the node, with host IPC/Network/PID namespaces and the node's `/` mounted at `/host`. |
| **Profile** | `legacy` (default, deprecated) and `general`: not privileged, default capabilities. `sysadmin`: `privileged: true`, all capabilities. |
| **Needs a working node** | It's a normal Pod: the kubelet must run it. A dead or unreachable node leaves it `Pending` forever. |
| **RBAC** | Creating Pods with `nodeName`/hostPath/host namespaces. Effectively node-root, so grant carefully. |

---

## Step 0
```bash
cd tasks/debug/debug-cluster/kubectl-node-debug
kubectl debug node/minikube -it --image=ubuntu --profile=general      # the docs' interactive way; exit to leave
```

## Lab 1 – What each profile can do (not from the docs)
```bash
for prof in legacy general sysadmin; do
  kubectl debug node/minikube --image=ubuntu --profile=$prof --attach=false -- sleep 300
  ND=$(kubectl get pods -o name --sort-by=.metadata.creationTimestamp | grep node-debugger | tail -1)
  kubectl get $ND -o jsonpath='{.spec.containers[0].securityContext}'; echo
  kubectl exec $ND -- sh -c 'chroot /host true && echo chroot-ok; head -c1 /proc/1/environ >/dev/null && echo environ-ok; nsenter -t 1 -m -- true && echo nsenter-ok; grep CapEff /proc/self/status'
  kubectl delete $ND --now
done
```
| | legacy | general | sysadmin |
|---|---|---|---|
| securityContext | *(none)* | *(none)* | `{"privileged":true}` |
| `chroot /host` (docs: "will fail") | **ok** | **ok** | ok |
| `chroot /host systemctl is-active kubelet` | active | active | active |
| `chroot /host journalctl -u kubelet` | works | works | works |
| read `/proc/1/environ` | denied | denied | ok |
| `nsenter -t 1 -m` (host mount namespace) | denied | denied | ok |
| CapEff | `a80425fb` | `a80425fb` | `000001ffffffffff` |
| processes visible (`ps -e`) | 61 (host PID namespace) | 61 | 61 |

## Lab 2 – Where are the logs? (docs paths)
```bash
kubectl debug node/minikube --image=ubuntu --profile=general --attach=false -- sleep 300
ND=$(kubectl get pods -o name | grep node-debugger | tail -1)
kubectl exec $ND -- sh -c 'for f in kubelet.log kube-proxy.log containerd.log syslog kern.log; do ls /host/var/log/$f; done'
#   … No such file or directory      (all five)
kubectl exec $ND -- chroot /host journalctl -u kubelet -n 3 --no-pager       # kubelet: journald
kubectl exec $ND -- chroot /host journalctl -u containerd -n 3 --no-pager    # containerd: journald
kubectl exec $ND -- ls /host/var/log/pods | head                             # kube-proxy & all Pods: /var/log/pods
kubectl delete $ND --now
```

## Lab 3 – A node that is down (the docs' note)
```bash
../../../../concepts/scheduling-eviction/fake-nodes.sh up 1                 # fake-1 …
kill $(cat ../../../../concepts/scheduling-eviction/.fake-nodes-minikube.pid)    # … whose "kubelet" then dies
kubectl debug node/fake-1 --image=ubuntu --profile=general --attach=false -- sleep 60
#   Creating debugging pod node-debugger-fake-1-t2rp8 with container debugger on node fake-1.
kubectl get pods -o wide | grep node-debugger-fake
#   node-debugger-fake-1-t2rp8   0/1   Pending   …   fake-1                    <- bound, but nobody will ever run it
```
For that case, follow [debugging a down/unreachable node](../#lab-1--a-downunreachable-node-docs-example-reproduced).

## Cleanup (docs)
```bash
kubectl get pods                                   # node-debugger-minikube-…   Completed
kubectl delete pod node-debugger-minikube-<x> --now
./cleanup.sh                                       # all debugger Pods (force for the fake node) + fake nodes
```
