# Leases – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/leases/

> Cluster: the 2-node profile **`arch-lab`** (see [../README.md](../README.md)). Lab 3 edits a static-pod manifest on the control plane. That's fine on this throw-away profile; `./cleanup.sh` puts it back.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Lease** | A small object (`coordination.k8s.io/v1`) used as a **lock** or **heartbeat**: `holderIdentity`, `leaseDurationSeconds`, `acquireTime`, `renewTime`, `leaseTransitions`. |
| **Node heartbeats** | One Lease per Node in `kube-node-lease`, with the **same name** as the node. Each kubelet heartbeat is an **update** of `spec.renewTime`, and the control plane uses that timestamp to decide whether the node is alive. |
| **Leader election** | In HA control planes, several kube-controller-manager / kube-scheduler instances run and **one** holds the Lease and works, while the others stand by. Optionally (feature gate `ControllerManagerReleaseLeaderElectionLockOnExit`), the controller-manager releases the lock when it exits so a successor takes over faster. |
| **API server identity** | Since v1.26 each kube-apiserver publishes a Lease `apiserver-<sha256(hostname)>` in `kube-system`, labelled `apiserver.kubernetes.io/identity=kube-apiserver`, with `leaseDurationSeconds: 3600`. Expired ones are garbage-collected after 1h. |
| **Your workloads** | You can use Leases for your own leader election. Name them after the component (`example-foo`) and avoid collisions when several instances may be deployed. |
| **Optimistic locking** | Updates carry the `resourceVersion` you read. If someone else wrote in between, you get **409 Conflict**, which is why two candidates can't both win. |

## The demo app
[01-example-foo-lease.yaml](01-example-foo-lease.yaml) is the Lease `example-foo` in `leases-demo`, with a 10s duration. [elect.sh](elect.sh) is a leader-election candidate in bash that does the same thing as client-go's `leaderelection` package, simplified.

---

## Step 1
```bash
cd concepts/architecture/leases
kubectl config use-context arch-lab
kubectl get lease -A
#   kube-node-lease   arch-lab                               arch-lab
#   kube-node-lease   arch-lab-m02                           arch-lab-m02
#   kube-system       apiserver-ioctspdw6inas6ya5ooxupcz2a   apiserver-ioctspdw6inas6ya5ooxupcz2a_24dd…
```
There's **no** `kube-controller-manager` or `kube-scheduler` lease. minikube starts both with `--leader-elect=false` because it runs only one copy of each (Lab 3 changes that).

## Lab 1 – Node heartbeats
```bash
kubectl get lease arch-lab-m02 -n kube-node-lease -o json | jq -c .spec
#   {"holderIdentity":"arch-lab-m02","leaseDurationSeconds":40,"renewTime":"…"}
kubectl get lease -n kube-node-lease -w -o custom-columns=NODE:.metadata.name,RENEWED:.spec.renewTime
#   a new line every ~10s per node - each line is one heartbeat (an UPDATE request)
```
In a second terminal stop the worker (`minikube node stop m02 -p arch-lab`). Its `renewTime` stops moving, and about 40–50s later the node becomes `NotReady`, as in Lab 6 of [../nodes](../nodes/). Start it again with `minikube node start m02 -p arch-lab`.

## Lab 2 – API server identity (the docs commands)
```bash
kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver
kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver -o yaml | grep -E 'hostname|leaseDurationSeconds|holderIdentity|renewTime'
#   kubernetes.io/hostname: arch-lab          <- the name hash comes from this hostname
#   holderIdentity: apiserver-…_<uuid>        <- a new uuid every API server restart; same Lease name
#   leaseDurationSeconds: 3600
```
One Lease means one API server. On an HA control plane you'd see one per instance, as in the docs' 3-line output.

## Lab 3 – Leader election for kube-controller-manager
Turn it on:
```bash
minikube ssh -p arch-lab -n arch-lab -- "sudo sed -i 's/--leader-elect=false/--leader-elect=true/' /etc/kubernetes/manifests/kube-controller-manager.yaml"
sleep 40          # the kubelet restarts the static pod
kubectl get lease kube-controller-manager -n kube-system -o json | jq -c .spec
#   {"acquireTime":"…","holderIdentity":"arch-lab_e1e27b71-…","leaseDurationSeconds":15,"leaseTransitions":0,"renewTime":"…"}
```
Simulate a leader crash and replacement:
```bash
minikube ssh -p arch-lab -n arch-lab -- "sudo mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/"
sleep 15 ; kubectl get lease kube-controller-manager -n kube-system -o jsonpath='{.spec.holderIdentity} {.spec.renewTime}{"\n"}'
#   arch-lab_e1e27b71-…  <old time>    <- the dead leader still "holds" it; renewTime frozen
minikube ssh -p arch-lab -n arch-lab -- "sudo mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/"
sleep 30 ; kubectl get lease kube-controller-manager -n kube-system -o jsonpath='{.spec.holderIdentity} transitions={.spec.leaseTransitions}{"\n"}'
#   arch-lab_c3560870-…  transitions=1 <- new instance acquired it once the old lease had expired
```
On v1.37 the lock was **not** released on exit: holder and renewTime stayed frozen. That matches the `ControllerManagerReleaseLeaderElectionLockOnExit` gate being **off by default**. With it on, the old holder clears the lock as it stops, and the successor doesn't wait out the 15s.

## Lab 4 – Leader election for your own workload
```bash
kubectl apply -f 00-namespace.yaml -f 01-example-foo-lease.yaml
```
Run three candidates in three terminals:
```bash
./elect.sh alice
./elect.sh bob
./elect.sh carol
```
Expected:
```
alice    *** became LEADER ***
alice    leader   (renewed)            bob/carol:  standby  (leader=alice, renewed 1s ago)
        ... press Ctrl-C in alice's terminal ...
bob/carol: standby (leader=alice, renewed 4s ago) ... (renewed 11s ago)   <- waiting out leaseDurationSeconds (10)
bob      *** became LEADER ***
carol    lost the race: the object has been modified       <- 409 Conflict: optimistic locking
```
```bash
kubectl get lease example-foo -n leases-demo -o json | jq -c .spec
#   {"acquireTime":"…","holderIdentity":"bob","leaseDurationSeconds":10,"leaseTransitions":1,"renewTime":"…"}
```
Why it's safe: each candidate sends back the `resourceVersion` it read, so only **one** update succeeds per version. The trade-off is the take-over delay (≈ leaseDuration), which is shorter leases versus more API writes.

---

## Useful commands
```bash
kubectl get lease -A
kubectl get lease -n kube-node-lease -w
kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver
kubectl get lease <name> -n <ns> -o jsonpath='{.spec.holderIdentity} {.spec.renewTime}'
```

## Cleanup
```bash
./cleanup.sh     # deletes leases-demo and sets --leader-elect=false again on kube-controller-manager
```
