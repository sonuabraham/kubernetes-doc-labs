# Advanced Pod Configuration – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/advanced-pod-config/

> This page is a tour, and each topic has its own deep-dive page. All 10 manifests from the page are here **verbatim**. Two pairs share names (`nginx`, `mypod`), so this lab uses namespaces **`adv-a`** and **`adv-b`**.

## Key ideas (read first)

| Topic | What it controls | Deep dive |
|---|---|---|
| **PriorityClass** | Scheduling order and **preemption**. A cluster-scoped `value` (higher wins). Built-ins `system-cluster-critical` (2000000000) and `system-node-critical` (2000001000). | `../../../scheduling-eviction/pod-priority-preemption` |
| **RuntimeClass** | Which runtime handler runs the Pod, plus optional **overhead**. | `../../../containers/runtime-class` |
| **securityContext (Pod)** | Defaults for all containers: `runAsUser`, `runAsGroup`, `fsGroup`, … | `../../../security/` |
| **securityContext (container)** | Overrides: `allowPrivilegeEscalation`, `runAsNonRoot`, `capabilities`, `seccompProfile`, SELinux, AppArmor. | |
| **nodeSelector** | Hard equality match on node labels. | `../../../scheduling-eviction/assign-pod-node` |
| **Node affinity** | Expressive node rules (required/preferred). | same |
| **Pod (anti-)affinity** | Place near or away from **other pods**, per `topologyKey` domain. | same |
| **Tolerations** | Allow scheduling onto **tainted** nodes. They don't attract. | `../../../scheduling-eviction/taint-and-toleration` |
| **Pod overhead** | Extra resources for the sandbox (from the RuntimeClass), counted in scheduling and quota. | `../../../scheduling-eviction/pod-overhead` |

## The demo app (verbatim docs manifests)
| File | Namespace in this lab |
|---|---|
| [priorityclass-high-priority.yaml](priorityclass-high-priority.yaml), [pod-with-priority.yaml](pod-with-priority.yaml) (`nginx`) | adv-a |
| [pod-with-runtimeclass.yaml](pod-with-runtimeclass.yaml) (`mypod`, class `myclass`) | dry-run only |
| [security-context-demo.yaml](security-context-demo.yaml), [security-context-demo-2.yaml](security-context-demo-2.yaml) | adv-a |
| [pod-nodeselector.yaml](pod-nodeselector.yaml) (`nginx`, `disktype: ssd`) | adv-b |
| [with-node-affinity.yaml](with-node-affinity.yaml), [pod-tolerations.yaml](pod-tolerations.yaml) (`mypod`) | adv-a |
| [with-pod-affinity.yaml](with-pod-affinity.yaml) + [01-database-pod.yaml](01-database-pod.yaml) | adv-b |
| [runtimeclass-overhead.yaml](runtimeclass-overhead.yaml) (`kvisor-runtime` + `mypod`) | adv-b |

---

## Step 1 – Apply everything
```bash
cd concepts/workloads/pods/advanced-pod-config
kubectl apply -f 00-namespaces.yaml -f priorityclass-high-priority.yaml
kubectl apply -n adv-a -f pod-with-priority.yaml -f security-context-demo.yaml -f security-context-demo-2.yaml -f with-node-affinity.yaml -f pod-tolerations.yaml
kubectl apply -n adv-b -f pod-nodeselector.yaml -f with-pod-affinity.yaml -f runtimeclass-overhead.yaml
sleep 20
kubectl get pods -n adv-a -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,PRIORITY:.spec.priority
kubectl get pods -n adv-b -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,OVERHEAD:.spec.overhead
```
Expected:
```
adv-a: nginx                     Running   10000    <- priorityClassName resolved into spec.priority
       security-context-demo     Running   0
       security-context-demo-2   Pending   0        <- see Lab 2
       with-node-affinity        Pending   0        <- no node in zone antarctica-*
       mypod                     Running   0        <- tolerations don't require a taint
adv-b: nginx                     Pending            <- no node labelled disktype=ssd
       with-pod-affinity         Pending            <- no app=database pod in its zone
       mypod                     Pending   map[cpu:500m memory:2Gi]   <- overhead copied from the RuntimeClass
```

## Lab 1 – PriorityClass
```bash
kubectl get priorityclass
#   high-priority             10000        false   PreemptLowerPriority
#   system-cluster-critical   2000000000   false
#   system-node-critical      2000001000   false      <- the highest possible
kubectl get pods -n kube-system -o custom-columns=NAME:.metadata.name,PC:.spec.priorityClassName | grep critical
```

## Lab 2 – Security contexts
```bash
kubectl exec security-context-demo -n adv-a -- id
#   uid=1000(user-defined-in-image) gid=3000 groups=2000,3000,...      <- Pod-level runAsUser/runAsGroup/fsGroup
kubectl get pod security-context-demo-2 -n adv-a -o jsonpath='{.status.containerStatuses[0].state.waiting.message}{"\n"}' | cut -c1-200
#   failed to pull ... "gcr.io/google-samples/node-hello:1.0": not implemented: media type "application/vnd.docker.distribution.manifest.v1+prettyjws" ...
```
The docs' second example uses an image published in the **Docker schema-1** format, which **containerd 2.x can't pull**. The `securityContext` itself is fine. To see it work, swap the image (`kubectl run` it with `--image=busybox:1.36 --overrides` that copy the same securityContext) and check `id` (uid 1000) and `grep Cap /proc/1/status` (all capabilities dropped).

## Lab 3 – RuntimeClass and overhead
```bash
kubectl create -f pod-with-runtimeclass.yaml -n default --dry-run=server
#   pods "mypod" is forbidden: pod rejected: RuntimeClass "myclass" not found
kubectl get pod mypod -n adv-b -o jsonpath='{.spec.overhead}{"\n"}'     # {"cpu":"500m","memory":"2Gi"}
```
Once scheduled (Lab 4), `mypod` in adv-b stays `ContainerCreating`: the `kvisor-runtime` handler doesn't exist on the node (`no runtime for "kvisor-runtime"`). Admission still added the overhead. A working handler is in `../../../containers/runtime-class`.

## Lab 4 – nodeSelector, node affinity, pod affinity
```bash
kubectl label node minikube disktype=ssd topology.kubernetes.io/zone=antarctica-east1
kubectl apply -f 01-database-pod.yaml ; sleep 10
kubectl get pods -n adv-a with-node-affinity     # Running - zone matches antarctica-east1
kubectl get pods -n adv-b                        # nginx Running (disktype=ssd), with-pod-affinity Running (database in the same zone)
```
`with-pod-affinity` needs **both** a node with a `topology.kubernetes.io/zone` label **and** an `app=database` pod in that zone.

## Lab 5 – Tolerations
```bash
kubectl get pod mypod -n adv-a -o jsonpath='{.spec.tolerations}{"\n"}'     # key=value:NoSchedule (+ the default not-ready/unreachable ones)
```
It runs although the node has **no** `key=value` taint. A toleration only *permits* a tainted node; it never pulls a pod towards one. (We don't taint the single minikube node here. See the taints page.)

---

## Useful commands
```bash
kubectl get priorityclass
kubectl explain pod.spec.securityContext ; kubectl explain pod.spec.affinity
kubectl describe pod <p> | sed -n '/Events/,$p'        # why a pod is Pending
```

## Cleanup
```bash
./cleanup.sh       # namespaces, PriorityClass, RuntimeClass, node labels
```
