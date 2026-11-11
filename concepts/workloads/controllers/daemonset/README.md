# DaemonSet – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/

> Single-node `minikube`, so "one per node" means one Pod. For a DaemonSet appearing on a **new** node, use the 2-node `arch-lab` profile (`../../../architecture`) and `minikube node add -p arch-lab`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **DaemonSet** | Runs one copy of a Pod on **all (or selected) nodes**. Nodes added later get one, removed nodes' Pods are garbage-collected. Typical uses: storage daemons, log collectors, node monitoring, CNI agents. |
| **Selecting nodes** | `.spec.template.spec.nodeSelector` / `affinity`. Without them, every node. |
| **Scheduling** | The DaemonSet controller adds a **node affinity per Pod** (`matchFields metadata.name In [<node>]`), and the **default scheduler** binds it. |
| **Automatic tolerations** | `not-ready`, `unreachable` (NoExecute), `disk-pressure`, `memory-pressure`, `pid-pressure`, `unschedulable` (NoSchedule), and `network-unavailable` for hostNetwork pods. So daemons keep running on cordoned or unhealthy nodes. |
| **Your tolerations** | For example the docs' `node-role.kubernetes.io/control-plane:NoSchedule`, to run on control-plane nodes too. |
| **Talking to daemons** | Push (the daemon sends out), **NodeIP + known port** (`hostPort`), DNS via a headless Service, or a normal Service. |
| **Updates** | `RollingUpdate` (default: replace pod by pod, `maxUnavailable`/`maxSurge`) or `OnDelete` (a new template applies only when you delete a pod). History via ControllerRevisions. |
| **Alternatives** | Init scripts, bare Pods, **static Pods** (kubelet only), Deployments (when it doesn't matter which node). |

## The demo app
[daemonset.yaml](daemonset.yaml) is the docs manifest **verbatim**: `fluentd-elasticsearch` in **`kube-system`**, tolerating control-plane nodes and mounting `/var/log`. [node-affinity-matchfields-excerpt.yaml](node-affinity-matchfields-excerpt.yaml) is the docs' affinity excerpt. [01-ssd-agent.yaml](01-ssd-agent.yaml) is a DaemonSet in `ds-demo`, only on `disk=ssd` nodes, with `OnDelete` and `hostPort: 8081`.

---

## Lab 1 – Create the docs DaemonSet
```bash
cd concepts/workloads/controllers/daemonset
kubectl apply -f daemonset.yaml
kubectl rollout status ds/fluentd-elasticsearch -n kube-system
kubectl get ds fluentd-elasticsearch -n kube-system       # DESIRED 1 CURRENT 1 READY 1 (one node)
kubectl get pods -n kube-system -l name=fluentd-elasticsearch -o wide
```

## Lab 2 – What the controller adds to each Pod
```bash
P=$(kubectl get pod -n kube-system -l name=fluentd-elasticsearch -o name)
kubectl get $P -n kube-system -o json | jq -c '.spec.affinity'
#   {"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchFields":[{"key":"metadata.name","operator":"In","values":["minikube"]}]}]}}}
kubectl get $P -n kube-system -o json | jq -r '.spec.tolerations[] | "\(.key):\(.effect)"'
#   node-role.kubernetes.io/control-plane:NoSchedule   <- from the manifest
#   node-role.kubernetes.io/master:NoSchedule          <- from the manifest
#   node.kubernetes.io/not-ready:NoExecute             <- the rest added automatically
#   node.kubernetes.io/unreachable:NoExecute
#   node.kubernetes.io/disk-pressure:NoSchedule
#   node.kubernetes.io/memory-pressure:NoSchedule
#   node.kubernetes.io/pid-pressure:NoSchedule
#   node.kubernetes.io/unschedulable:NoSchedule
```
Each Pod is pinned to **its** node by `matchFields`. That's the docs' "How Daemon Pods are scheduled" excerpt in action.

## Lab 3 – Running only on selected nodes
```bash
kubectl apply -f 01-ssd-agent.yaml
kubectl get ds ssd-agent -n ds-demo                 # DESIRED 0 - no node has disk=ssd
kubectl label node minikube disk=ssd
kubectl get pods -n ds-demo -w                      # a pod appears
curl -s http://$(minikube ip):8081/hostname ; echo  # ssd-agent-xxxxx  <- reached via NodeIP + hostPort
kubectl label node minikube disk-
kubectl get pods -n ds-demo                         # the pod is removed - node no longer matches
```

## Lab 4 – Update strategies
OnDelete (`ssd-agent`):
```bash
kubectl label node minikube disk=ssd ; kubectl wait --for=condition=Ready pod -l app=ssd-agent -n ds-demo
kubectl set image ds/ssd-agent agent=registry.k8s.io/e2e-test-images/agnhost:2.52 -n ds-demo
kubectl get pods -n ds-demo -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image    # still 2.53
kubectl delete pod -n ds-demo -l app=ssd-agent
kubectl get pods -n ds-demo -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image    # new pod: 2.52
kubectl rollout status ds/ssd-agent -n ds-demo      # error: rollout status is only available for RollingUpdate strategy type
```
RollingUpdate (the docs DaemonSet):
```bash
kubectl set image ds/fluentd-elasticsearch fluentd-elasticsearch=quay.io/fluentd_elasticsearch/fluentd:v5.0.0 -n kube-system
kubectl rollout status ds/fluentd-elasticsearch -n kube-system
kubectl rollout history ds/fluentd-elasticsearch -n kube-system     # 1, 2
kubectl rollout undo ds/fluentd-elasticsearch -n kube-system
```

---

## Useful commands
```bash
kubectl get ds -A                       # kube-proxy and kindnet are DaemonSets too
kubectl rollout status|history|undo ds/<name> -n <ns>
kubectl get pods -l <selector> -o wide  # which node each daemon pod is on
```

## Cleanup
```bash
./cleanup.sh       # deletes the docs DaemonSet from kube-system, the ds-demo namespace and the node label
```
