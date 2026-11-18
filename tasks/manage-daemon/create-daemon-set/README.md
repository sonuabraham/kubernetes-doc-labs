# Building a Basic DaemonSet – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/manage-daemon/create-daemon-set/

> Runs on the default **minikube** cluster (one node, so one Pod; the docs suggest two nodes). File: [basic-daemonset.yaml](basic-daemonset.yaml) (docs, **verbatim**).
>
> **Found:**
> 1. The check `kubectl exec <pod-name> -- cat /var/log/machine-id.log` **can't work**. `exec` goes to the main container, `pause`, which has no `cat`
>    (`exec: "cat": executable file not found in $PATH`) and doesn't mount `/var/log` anyway; only the init container does.
>    The file is on the **node** (hostPath), so read it there: `minikube ssh` or `kubectl debug node/…`.
> 2. The DaemonSet writes `/var/log/machine-id.log` onto the host, and deleting the DaemonSet leaves it there. [cleanup.sh](cleanup.sh) removes it.
> 3. `registry.k8s.io/pause` has no tag (`:latest`, `imagePullPolicy: Always`). Pin a version in real manifests.

## Key ideas (read first)

| Piece | Role |
|---|---|
| DaemonSet | one Pod per (matching) node; new nodes get one automatically |
| init container `log-machine-id` | runs once per Pod: copies the host's `/etc/machine-id` to the host's `/var/log/machine-id.log` |
| `pause` main container | keeps the Pod Running and doesn't do anything |
| hostPath `type: File` | the Pod fails to start if `/etc/machine-id` is missing on a node |

---

## Lab 1 – Create and check (docs)
```bash
cd tasks/manage-daemon/create-daemon-set
kubectl apply -f basic-daemonset.yaml
kubectl get pods -o wide -l app.kubernetes.io/name=example
#   example-daemonset-2g78v   1/1   Running   0   4s   10.244.0.9   minikube        <- one per node
kubectl exec example-daemonset-2g78v -- cat /var/log/machine-id.log
#   … exec: "cat": executable file not found in $PATH                              <- Found #1
minikube ssh -- "cat /var/log/machine-id.log; cat /etc/machine-id"
#   b7566eefbea02b7ce85821e86a97158b
#   b7566eefbea02b7ce85821e86a97158b                                                <- copied from the host, written to the host
kubectl debug node/minikube --image=busybox:1.36 -q -- cat /host/var/log/machine-id.log    # the same through the API (node root at /host)
kubectl logs node-debugger-minikube-<xxxxx>                                         # b7566eefbea02b7ce85821e86a97158b
```

## Lab 2 – Delete (docs)
```bash
kubectl delete --cascade=foreground --ignore-not-found --now daemonsets/example-daemonset
kubectl get ds,pods -l app.kubernetes.io/name=example         # No resources found
minikube ssh -- ls -l /var/log/machine-id.log                   # still there (Found #2)
```
More DaemonSet behaviour (tolerations, node selection, multiple nodes): [concepts/…/daemonset](../../../concepts/workloads/controllers/daemonset/)
and [pods-some-nodes](../pods-some-nodes/).

## Cleanup
```bash
./cleanup.sh
```
