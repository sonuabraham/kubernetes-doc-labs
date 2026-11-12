# Pod Overhead – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/pod-overhead/

> The docs' RuntimeClass and Pod are **verbatim**: [01-runtimeclass-kata-fc.yaml](01-runtimeclass-kata-fc.yaml), [02-test-pod.yaml](02-test-pod.yaml). minikube has no Kata Containers, so [03-runtimeclass-runc-overhead.yaml](03-runtimeclass-runc-overhead.yaml) declares the same overhead on the `runc` handler, letting the Pod really run and its cgroup be inspected.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Pod overhead** | Resources the **sandbox** itself uses (VM, guest kernel, agent for Kata or gVisor), on top of the containers' requests. |
| **Where it's set** | `RuntimeClass.overhead.podFixed`. The **RuntimeClass admission controller** copies it into `pod.spec.overhead` at creation. You can't set a different value yourself. |
| **Scheduling** | Request sum = containers + overhead. ResourceQuota counts it too. |
| **Enforcement** | kubelet sizes the **pod cgroup** = sum of container limits + overhead (when all containers have limits). |
| **Observability** | `kube_pod_overhead_*` metrics (kube-state-metrics); `kubectl describe node` includes it. |

---

## Lab 1 – Overhead added at admission (docs)
```bash
cd concepts/scheduling-eviction/pod-overhead
kubectl create ns po-demo
kubectl apply -f 01-runtimeclass-kata-fc.yaml -f 03-runtimeclass-runc-overhead.yaml
kubectl apply -n po-demo -f 02-test-pod.yaml
kubectl get pod test-pod -n po-demo -o jsonpath='{.spec.overhead}'                     # {"cpu":"250m","memory":"120Mi"}
kubectl get pod test-pod -n po-demo -o jsonpath='{.spec.containers[*].resources.limits}'
#   {"cpu":"500m","memory":"100Mi"} {"cpu":"1500m","memory":"100Mi"}
kubectl get events -n po-demo --field-selector involvedObject.name=test-pod -o custom-columns=M:.message | tail -1
#   Failed to create pod sandbox: ... no runtime for "kata-fc" is configured        <- scheduled, but the handler doesn't exist here
kubectl run withoh -n po-demo --image=busybox:1.36 --overrides='{"spec":{"runtimeClassName":"kata-fc","overhead":{"cpu":"1"},"containers":[{"name":"c","image":"busybox:1.36"}]}}'
#   forbidden: pod rejected: Pod's Overhead doesn't match RuntimeClass's defined Overhead
```

## Lab 2 – Scheduling and node accounting
```bash
sed 's/name: test-pod/name: test-pod-runc/; s/runtimeClassName: kata-fc/runtimeClassName: runc-overhead/' 02-test-pod.yaml | kubectl apply -n po-demo -f -
kubectl describe node minikube | grep test-pod
#   po-demo  test-pod        2250m (28%)  2250m (28%)  320Mi (1%)  320Mi (1%)
#   po-demo  test-pod-runc   2250m (28%)  2250m (28%)  320Mi (1%)  320Mi (1%)     <- 500m+1500m+250m, 100+100+120Mi
```
The docs' output shows 56% on a 4-CPU node; this node has 8.

## Lab 3 – The pod cgroup includes the overhead
```bash
minikube ssh -- 'POD_ID="$(sudo crictl pods --name test-pod-runc -q)"; sudo crictl inspectp -o=json $POD_ID | grep cgroupsPath'
#   "cgroupsPath": "kubepods-pod67ffd318_2830_….slice:cri-containerd:7cc3…"      <- systemd cgroup driver, cgroup v2 (docs show v1 paths)
minikube ssh -- 'S=$(sudo crictl inspectp -o=json $(sudo crictl pods --name test-pod-runc -q) | grep -o "kubepods-pod[0-9a-f_]*\.slice" | head -1); cat /sys/fs/cgroup/kubepods.slice/$S/memory.max /sys/fs/cgroup/kubepods.slice/$S/cpu.max'
#   335544320                   <- 320Mi, exactly the docs' memory.limit_in_bytes
#   225000 100000               <- 2.25 CPU
```
On cgroup v2 the file is `memory.max` (the docs' `memory/…/memory.limit_in_bytes` is cgroup v1).

---

## Useful commands
```bash
kubectl get runtimeclass -o custom-columns=NAME:.metadata.name,HANDLER:.handler,OVERHEAD:.overhead.podFixed
kubectl get pod <p> -o jsonpath='{.spec.overhead}'
```

## Cleanup
```bash
./cleanup.sh
```
