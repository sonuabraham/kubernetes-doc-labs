# Node Shutdowns – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/

> The docs' priority-based config snippet is **verbatim** in [shutdown-grace-by-priority-excerpt.yaml](shutdown-grace-by-priority-excerpt.yaml). **Graceful** shutdown needs a kubelet with grace periods and a real shutdown: throwaway profile **`shutdown-lab`** ([start-shutdown-lab.sh](start-shutdown-lab.sh), 30s / 10s like the docs' example). **Non-graceful** handling uses a fake node (`../../scheduling-eviction/fake-nodes.sh`) that "dies".

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Graceful node shutdown** | The kubelet takes a systemd-logind **inhibitor lock** (delay) and learns of a shutdown in time. It sets the node `NotReady` ("node is shutting down"), rejects new Pods, and terminates Pods in two phases: regular, then critical. |
| **Settings** | `shutdownGracePeriod` (total) and `shutdownGracePeriodCriticalPods` (the last part). Both **0 by default = off**. 30s/10s → 20s for regular Pods, 10s for critical ones. |
| **By Pod priority** | `shutdownGracePeriodByPodPriority`: grace periods per priority band (the docs snippet). |
| **Pod outcome** | Terminated Pods get condition `DisruptionTarget` / reason `TerminationByKubelet`. Controllers recreate them elsewhere. |
| **Non-graceful** | The node vanished without notice: Pods on it hang in `Terminating`, and StatefulSet Pods / RWO volumes are stuck. An admin adds taint `node.kubernetes.io/out-of-service` (NoExecute) after making sure the node is **really** down. Pods are then force-deleted and volumes detached. |
| **Forced detach on timeout** | The attach/detach controller force-detaches after 6 min of a node being unhealthy (can be disabled). |

---

## Lab 1 – Graceful shutdown (shutdown-lab)
```bash
cd concepts/cluster-administration/node-shutdown
./start-shutdown-lab.sh
#   {"shutdownGracePeriod":"30s","shutdownGracePeriodCriticalPods":"10s"}
#   kubelet  0 root 1551 kubelet shutdown  Kubelet needs time to handle node …  delay      <- the inhibitor lock
minikube -p shutdown-lab ssh -- "cat /etc/systemd/logind.conf.d/*.conf"     # InhibitDelayMaxSec=30 (written by the kubelet)
kubectl --context shutdown-lab apply -f 01-pods.yaml     # "regular" (default ns) and "critical" (system-node-critical, kube-system)
minikube -p shutdown-lab ssh -- "sudo systemctl poweroff"
```
Watched from the host every second:
```
18:31:51  node=True/kubelet is posting ready status   regular=Running  critical=Running
18:31:52  node=False/node is shutting down            regular=Running  critical=Running
18:31:57  (API unreachable - the node, which also runs the control plane, was gone)
```
After `minikube start -p shutdown-lab`:
```bash
kubectl --context shutdown-lab get pod regular -o jsonpath='{.status.phase}'      # Succeeded   (its SIGTERM trap exits 0)
kubectl --context shutdown-lab get pod regular -o jsonpath='{.status.conditions}' | jq -c '.[] | select(.type=="DisruptionTarget")'
#   {"message":"Pod was terminated in response to imminent node shutdown.","reason":"TerminationByKubelet","status":"True","type":"DisruptionTarget"}
```
The kubelet saw the shutdown, flipped the node to NotReady with the documented reason, and terminated the regular Pod with the shutdown condition. The full 30s window wasn't observable: this node is also the control plane, and the docker-driver container went down after ~6s.

## Lab 2 – Non-graceful shutdown and out-of-service (main cluster, fake node)
```bash
../../scheduling-eviction/fake-nodes.sh up 1 ; kubectl create ns shutdown-demo
# a Deployment with a Pod on fake-1, then the node "dies":
kill $(cat ../../scheduling-eviction/.fake-nodes-minikube.pid)
#   ~50s: fake-1 tainted node.kubernetes.io/unreachable (NoExecute)
kubectl delete pod -n shutdown-demo -l app=web --wait=false
#   web-…-kl277  Terminating  fake-1        <- stuck: no kubelet will ever confirm
kubectl taint nodes fake-1 node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
#   pods on fake-1 force-deleted after 13s  <- PodGC removes them; volumes would be detached too
```
Only add `out-of-service` when the node is **really** powered off, or two copies of a StatefulSet Pod could write to the same volume.

---

## Useful commands
```bash
kubectl get --raw /api/v1/nodes/<n>/proxy/configz | jq '.kubeletconfig | {shutdownGracePeriod, shutdownGracePeriodCriticalPods, shutdownGracePeriodByPodPriority}'
minikube ssh -- systemd-inhibit --list
kubectl get pods -A -o json | jq -r '.items[] | select(any(.status.conditions[]?; .reason=="TerminationByKubelet")) | .metadata.name'
```

## Cleanup
```bash
./cleanup.sh
```
