# Force Delete StatefulSet Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/run-application/force-delete-stateful-set-pod/

> Runs on a **throwaway 2-node minikube profile** `force-lab` ([start-force-lab.sh](start-force-lab.sh) stops the default profile first).
> The page has no manifest. [web-statefulset.yaml](web-statefulset.yaml) (**not from the docs**) is a 2-replica StatefulSet whose Pods print
> "I am web-N on NODE" every second. Node failure is simulated by stopping the kubelet on `force-lab-m02`; its containers keep running.
>
> **Result:** the page's warning is real. After `--grace-period=0 --force`, **two `web-0` processes ran at the same time** on different nodes,
> until the kubelet came back and killed the old one.

## Key ideas (read first)

| Situation | What happens |
|---|---|
| Graceful `kubectl delete pod` on an unreachable node | `Terminating` **forever**: only the kubelet may confirm the kill |
| Ways out | the node comes back (kubelet finishes it), you delete the **Node** object, or you force delete |
| `--grace-period=0 --force` | removes the API object at once without asking the kubelet → StatefulSet creates a new Pod with the **same name** |
| "At most one" | broken if the old container is still running: same identity twice (split brain) |
| Finalizers | force delete doesn't skip them; `patch … finalizers: null` does |

---

## Step 0
```bash
cd tasks/run-application/force-delete-stateful-set-pod
./start-force-lab.sh                       # force-lab (control plane) + force-lab-m02
kubectl apply -f web-statefulset.yaml
kubectl get pods -o wide
#   web-0   Running   force-lab-m02
#   web-1   Running   force-lab
```
(If both land on the same node, `kubectl delete pod web-0` until web-0 is on m02.)

## Lab 1 – Unreachable node, graceful delete hangs (docs)
```bash
minikube ssh -p force-lab -n force-lab-m02 -- sudo systemctl stop kubelet
kubectl get nodes                          # force-lab-m02 NotReady   (~55 s later)
kubectl describe node force-lab-m02 | grep -A1 Taints
#   node.kubernetes.io/unreachable:NoExecute
#   node.kubernetes.io/unreachable:NoSchedule
kubectl delete pod web-0 --wait=false
kubectl get pods -o wide                   # web-0   Terminating   force-lab-m02    <- and stays so
minikube ssh -p force-lab -n force-lab-m02 -- sudo crictl ps --name app
#   … Running   app   …   web-0             <- the container is still alive
```

## Lab 2 – Force delete → two web-0 (docs + proof)
```bash
kubectl delete pods web-0 --grace-period=0 --force
#   Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. …
#   pod "web-0" force deleted
kubectl get pods -o wide                   # web-0   Running   force-lab   AGE 0s   <- replacement
kubectl logs web-0 --tail=1
#   11:17:29 I am web-0 on force-lab
minikube ssh -p force-lab -n force-lab-m02 -- 'sudo crictl ps --name app -q | xargs -r sudo crictl logs --tail=2'
#   11:17:28 I am web-0 on force-lab-m02
#   11:17:29 I am web-0 on force-lab-m02    <- same second, same identity, two places
```
If web-0 were a database member with network access to its peers, both copies would act as `web-0`.

## Lab 3 – The kubelet cleans up when it returns (docs)
```bash
minikube ssh -p force-lab -n force-lab-m02 -- sudo systemctl start kubelet
minikube ssh -p force-lab -n force-lab-m02 -- sudo crictl ps -a --name app
#   … Exited   app   …   web-0             <- killed ~2 s after the node was Ready again (its Pod no longer exists in the API)
```
That's why the docs prefer waiting for the node (or deleting the Node object when it's really dead) over force deletion.

## Lab 4 – Finalizers (docs' last command)
```bash
kubectl patch pod web-1 -p '{"metadata":{"finalizers":["example.com/block"]}}'
kubectl delete pods web-1 --grace-period=0 --force --wait=false
kubectl get pods                           # web-1   0/1   Error      <- container killed, object still there
kubectl get pod web-1 -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}'
#   2026-11-16T11:17:42Z ["example.com/block"]
kubectl patch pod web-1 -p '{"metadata":{"finalizers":null}}'
kubectl get pods                           # web-1   1/1   Running   1s    <- new Pod
```
Only remove finalizers you understand: they usually guard cleanup work of a controller.

## Cleanup
```bash
./cleanup.sh          # deletes the force-lab profile and starts the default minikube again
```
