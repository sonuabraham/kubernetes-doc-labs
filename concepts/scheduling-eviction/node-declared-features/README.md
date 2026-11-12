# Node Declared Features – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/node-declared-features/

> The docs' Pod is **verbatim** in [example-pod.yaml](example-pod.yaml), and the Node status example in [node-declared-features-status-excerpt.yaml](node-declared-features-status-excerpt.yaml). minikube's real node declares its features. The **fake nodes** (`../fake-nodes.sh up 3`) declare none, which makes them perfect "old kubelet" stand-ins.

## Key ideas (read first)

| Step | What happens |
|---|---|
| **kubelet** | At startup, lists node-level features that are still graduating (and enabled) in `node.status.declaredFeatures`. |
| **scheduler** | Plugin `NodeDeclaredFeatures`: PreFilter infers the features a Pod **needs** from its spec, and Filter drops nodes that don't declare them. |
| **admission** | `NodeDeclaredFeatureValidator` (optional plugin) rejects Pods/updates needing features the **bound** node lacks. |
| **kubelet admission** | Final check before running. |
| **After GA** | Each feature has a `MaxVersion`. Newer kubelets stop declaring it, and everyone assumes it's available. |
| **Why** | Version skew: during upgrades some nodes are older. A Pod using a new feature must not land on a node that would ignore it. |

---

## Lab 1 – What this node declares
```bash
cd concepts/scheduling-eviction/node-declared-features
kubectl get node minikube -o jsonpath='{.status.declaredFeatures}'
#   ["ExtendWebSocketsToKubelet","InPlacePodLevelResourcesVerticalScaling","InPlacePodVerticalScalingInitContainers","RestartAllContainersOnContainerExits"]
kubectl get node fake-1 -o jsonpath='[{.status.declaredFeatures}]'        # []   - behaves like an older kubelet
```

## Lab 2 – Scheduling follows declared features
```bash
kubectl create ns ndf-demo
kubectl apply -n ndf-demo -f example-pod.yaml          # docs: restartPolicyRules → needs RestartAllContainersOnContainerExits
kubectl get pod example-pod -n ndf-demo -o wide        # Completed   minikube
# plain Pods spread anywhere (minikube, fake-3, fake-1); the same restartPolicyRules Pod with nodeSelector type=fake:
#   0/4 nodes are available: 1 node(s) didn't match Pod's node affinity/selector, 3 node(s) didn't match Pod's required features.
# and with nodeName: fake-2 (bypassing the scheduler):
#   pod/ex-pinned created          <- NodeDeclaredFeatureValidator isn't in minikube's admission plugin list
```
On a real old node the kubelet itself would then reject it (kubelet admission).

## Lab 3 – The feature itself: RestartAllContainers
```bash
kubectl apply -n ndf-demo -f 01-restart-all.yaml       # main exits 42 twice, then stays up; helper is a second container
kubectl get pod restart-all -n ndf-demo -o jsonpath='{range .status.containerStatuses[*]}{.name} restarts={.restartCount} {end}'
#   helper restarts=2 main restarts=2        <- main's exit 42 restarted ALL containers, in place (same Pod UID)
kubectl logs restart-all -n ndf-demo -c main            # run 3   (counter kept in the emptyDir across restarts)
```

---

## Useful commands
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,DECLARED:.status.declaredFeatures
kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]' | grep admission
```

## Cleanup
```bash
./cleanup.sh
```
