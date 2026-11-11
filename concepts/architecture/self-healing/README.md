# Kubernetes Self-Healing – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/self-healing/

> Cluster: the 2-node **`arch-lab`** profile (see [../README.md](../README.md)). Most pods are pinned to `arch-lab`. Lab 6 stops the worker.

## Key ideas (read first)

| Capability | Who does it | How |
|---|---|---|
| **Container restarts** | **kubelet** | Restarts failed containers according to the Pod's `restartPolicy` (`Always`, `OnFailure`, `Never`), with an exponential back-off (CrashLoopBackOff). |
| **Replica replacement** | **ReplicaSet / Deployment / StatefulSet controllers** | Create a replacement Pod to keep `replicas`. A **DaemonSet** replaces its Pod **on the same node**. |
| **Storage recovery** | **PersistentVolume controller** (+ attach/detach) | The replacement Pod gets the **same PVC**. If the node died, the volume is reattached on another node when the storage allows it. |
| **Service load balancing** | **EndpointSlice controller** | Failed or not-ready Pods are taken out of the Service's endpoints, so traffic only goes to healthy Pods. |
| **Node-level** | Node controller, node autoscaler | Pods on a dead node are evicted and recreated elsewhere. Autoscalers replace the machine. |
| **Limits** | – | An unavailable volume may need manual recovery. A restart doesn't fix **application bugs**. |

## The demo app
[00-restart-policies.yaml](00-restart-policies.yaml) creates namespace `healing-demo` and 4 pods that exit after 3s. [01-workloads.yaml](01-workloads.yaml) adds Deployment `web` (3, readiness = `/tmp/ready` exists) plus Service `web`, StatefulSet `db` (1, with a PVC, appends a line to `/data/log` at each start), and DaemonSet `agent`.

---

## Step 1
```bash
cd concepts/architecture/self-healing
kubectl config use-context arch-lab
kubectl apply -f 00-restart-policies.yaml -f 01-workloads.yaml
sleep 50
```

## Lab 1 – Container restarts (kubelet + restartPolicy)
```bash
kubectl get pods -n healing-demo -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount | grep -E 'always|onfailure|never'
```
Expected after ~50s:

| Pod | Exit | restartPolicy | Result |
|---|---|---|---|
| `always` | 1 | Always | Running/CrashLoopBackOff, RESTARTS 3+ |
| `onfailure` | 1 | OnFailure | Running/CrashLoopBackOff, RESTARTS 3+ |
| `onfailure-success` | 0 | OnFailure | **Succeeded**, 0 restarts (a clean exit isn't a failure) |
| `never` | 1 | Never | **Failed**, 0 restarts |

```bash
kubectl get pod always -n healing-demo -w            # gaps between restarts grow: 10s, 20s, 40s ... up to 5 min (back-off)
```
That's the docs' consideration: the kubelet keeps restarting, but the **bug** (`exit 1`) never goes away.

## Lab 2 – Replica replacement
```bash
kubectl delete pod -n healing-demo $(kubectl get pod -n healing-demo -l app=web -o name | head -1 | cut -d/ -f2)
kubectl get pods -n healing-demo -l app=web          # still 3 - one with a NEW random name (Deployment/ReplicaSet)
kubectl delete pod db-0 -n healing-demo
kubectl get pods -n healing-demo -l app=db -w        # db-0 comes back with the SAME name (StatefulSet identity)
A=$(kubectl get pod -n healing-demo -l app=agent --field-selector spec.nodeName=arch-lab-m02 -o name)
kubectl delete $A -n healing-demo
kubectl get pods -n healing-demo -l app=agent -o wide   # the new agent pod is on arch-lab-m02 again (DaemonSet: same node)
```

## Lab 3 – Persistent storage follows the replacement
```bash
kubectl exec db-0 -n healing-demo -- cat /data/log
#   started 11:38:39 as db-0
#   started 11:40:00 as db-0        <- the new pod mounted the SAME volume (PVC data-db-0) and found the old data
kubectl get pvc -n healing-demo                       # data-db-0 Bound - outlives every pod
```
On a cloud with network disks, the same thing works **across nodes**: the attach/detach controller moves the disk to the new node. minikube's hostPath storage lives on one node, which is why `db` is pinned to `arch-lab` here.

## Lab 4 – Services stop sending traffic to unhealthy pods
```bash
P=$(kubectl get pod -n healing-demo -l app=web -o name | head -1)
kubectl exec $P -n healing-demo -- rm /tmp/ready      # make it fail its readiness probe
sleep 5
kubectl get endpointslice -n healing-demo -l kubernetes.io/service-name=web -o json | jq -c '[.items[0].endpoints[] | {pod: .targetRef.name, ready: .conditions.ready}]'
#   [{"pod":"web-…-z8wjs","ready":true},{"pod":"web-…-qjb7k","ready":true},{"pod":"web-…-hv4sh","ready":false}]
kubectl get $P -n healing-demo                        # 0/1 Running - not restarted (readiness ≠ liveness), just no traffic
kubectl exec $P -n healing-demo -- touch /tmp/ready   # healthy again -> back in the endpoints
```

## Lab 5 – What self-healing can't do
```bash
kubectl describe pod always -n healing-demo | grep -E 'Last State|Exit Code|Reason|Restart Count'
#   Reason: Error   Exit Code: 1   Restart Count: N      <- fix the app; Kubernetes only restarts it
kubectl exec db-0 -n healing-demo -- cat /data/log    # some "started ..." lines
kubectl delete pvc data-db-0 -n healing-demo --wait=false   # Terminating - pvc-protection while db-0 uses it
kubectl delete pod db-0 -n healing-demo
kubectl get pod db-0 -n healing-demo ; kubectl get pvc -n healing-demo   # db-0 Running, data-db-0 Bound (age: seconds - a NEW claim)
kubectl exec db-0 -n healing-demo -- cat /data/log
#   started 11:42:10 as db-0     <- ONE line: the StatefulSet "healed" by creating a fresh, EMPTY volume

```

Everything looks healthy again, but the **data is gone**. Self-healing restores the desired *objects*, not your data. That's the docs' "storage failures may require recovery steps": backups and snapshots (`../../storage/volume-snapshots`).

## Lab 6 – Node-level healing
```bash
kubectl apply -f 01-workloads.yaml                    # (if you deleted things in Lab 5, recreate the namespace's objects)
kubectl get pods -n healing-demo -l app=agent -o wide
minikube node stop m02 -p arch-lab
```
After ~5 minutes (default tolerations), pods on `arch-lab-m02` are evicted, and Deployment pods would be recreated on `arch-lab`. The DaemonSet pod for m02 just waits, because it belongs to that node. See [../nodes](../nodes/) Lab 6 for the measured timeline. A node autoscaler (cluster-autoscaler, Karpenter) would also **replace the machine**.
```bash
minikube node start m02 -p arch-lab
```

---

## Useful commands
```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount
kubectl describe pod <pod> | grep -A5 'Last State'
kubectl get endpointslices -l kubernetes.io/service-name=<svc> -o yaml
kubectl get events --field-selector reason=BackOff
```

## Cleanup
```bash
./cleanup.sh
```
