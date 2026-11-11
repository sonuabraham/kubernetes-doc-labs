# Runtime Class – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/containers/runtime-class/

> Cluster: default **`minikube`** (containerd). [add-handler.sh](add-handler.sh) does the docs' **step 1**: it adds a containerd runtime handler named **`myconfiguration`**, so the docs' RuntimeClass `myclass` really works. It's runc with different settings (cgroupfs driver). [remove-handler.sh](remove-handler.sh) undoes it. Both restart containerd; running containers keep running.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **RuntimeClass** | Cluster-scoped (`node.k8s.io/v1`, stable since 1.20). It picks the **container runtime configuration** for a Pod: a different runtime (gVisor, Kata = VM isolation; more security, more overhead) or the **same runtime with different settings**. |
| **Two fields** | `metadata.name` (what Pods reference) and `handler` (the name of a CRI configuration on the node; must be a DNS label). |
| **Setup** | 1. Configure the handler in the CRI. containerd: `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.<HANDLER>]` in `/etc/containerd/config.toml`. CRI-O: `[crio.runtime.runtimes.<HANDLER>]`. 2. Create the RuntimeClass. |
| **Usage** | `spec.runtimeClassName: myclass`. Without it, the runtime's default handler is used. |
| **Scheduling** | `scheduling.nodeSelector` is **merged** into the pod's nodeSelector (a conflict means the pod is rejected), and `scheduling.tolerations` are added. Use this when only some nodes have the handler. |
| **Overhead** | `overhead.podFixed` is copied to `pod.spec.overhead` and **added** to the pod's requests by the scheduler, kubelet and quota (VM-based runtimes cost extra). |
| **Who may write** | RuntimeClasses should be admin-only. |

## The demo app
[runtimeclass.yaml](runtimeclass.yaml) is the docs' `myclass` → `myconfiguration`, **verbatim**. [mypod.yaml](mypod.yaml) is the docs' `mypod` (the `# ...` part filled with one container). [01-scheduling-overhead.yaml](01-scheduling-overhead.yaml) is RuntimeClass `sandboxed` with scheduling + overhead, plus a pod. [02-unknown-class.yaml](02-unknown-class.yaml) references a class that doesn't exist.

---

## Lab 1 – A RuntimeClass whose handler isn't configured
```bash
cd concepts/containers/runtime-class
kubectl apply -f 00-namespace.yaml -f runtimeclass.yaml
kubectl get runtimeclass                                     # myclass   myconfiguration
kubectl apply -f mypod.yaml -n runtimeclass-demo ; sleep 8
kubectl get pod mypod -n runtimeclass-demo                   # ContainerCreating (stuck)
kubectl get events -n runtimeclass-demo --field-selector involvedObject.name=mypod -o custom-columns=R:.reason,M:.message | tail -1
#   FailedCreatePodSandBox   ... unable to get OCI runtime for sandbox ...: no runtime for "myconfiguration" is configured
```
The docs say such a pod "will enter the `Failed` phase". On v1.37 + containerd it stays **ContainerCreating**, and the kubelet keeps retrying the sandbox.

## Lab 2 – Configure the handler on the node (docs step 1)
```bash
./add-handler.sh
#   [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.myconfiguration]
#     runtime_type = "io.containerd.runc.v2"
#     [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.myconfiguration.options]
#       SystemdCgroup = false
kubectl delete pod mypod -n runtimeclass-demo --grace-period=0 --force
kubectl apply -f mypod.yaml -n runtimeclass-demo
kubectl wait --for=condition=Ready pod/mypod -n runtimeclass-demo        # condition met
kubectl run normal -n runtimeclass-demo --image=busybox:1.36 -- sleep 600 ; kubectl wait --for=condition=Ready pod/normal -n runtimeclass-demo
minikube ssh -- "sudo crictl inspectp \$(sudo crictl pods --name '^mypod\$' -q) | grep -m1 runtimeHandler"     # "runtimeHandler": "myconfiguration"
minikube ssh -- "sudo crictl inspectp \$(sudo crictl pods --name '^normal\$' -q) | grep -m1 runtimeHandler"    # "runtimeHandler": ""   (default = runc)
```
Want **real** isolation instead? `minikube addons enable gvisor` installs the `runsc` handler and a `gvisor` RuntimeClass. Then `kubectl exec <pod> -- dmesg` shows gVisor's own kernel messages.

## Lab 3 – A RuntimeClass that doesn't exist
```bash
kubectl apply -f 02-unknown-class.yaml
#   Error from server (Forbidden): pods "no-such-class" is forbidden: pod rejected: RuntimeClass "does-not-exist" not found
```
Rejected at **admission** by the RuntimeClass admission plugin, which fills in overhead and scheduling. The pod never exists.

## Lab 4 – Scheduling: nodeSelector + tolerations merged into the pod
```bash
kubectl apply -f 01-scheduling-overhead.yaml ; sleep 3
kubectl get pod sandboxed-pod -n runtimeclass-demo -o json | jq -c '{nodeSelector: .spec.nodeSelector, tolerations: [.spec.tolerations[] | select(.key|test("runtime"))], phase: .status.phase}'
#   {"nodeSelector":{"runtime.example.com/sandbox":"true"},"tolerations":[{"key":"runtime.example.com/sandbox-only",...}],"phase":"Pending"}
kubectl label node minikube runtime.example.com/sandbox=true     # "this node has the handler"
kubectl get pod sandboxed-pod -n runtimeclass-demo               # Running
kubectl run conflict -n runtimeclass-demo --image=busybox:1.36 \
  --overrides='{"spec":{"runtimeClassName":"sandboxed","nodeSelector":{"runtime.example.com/sandbox":"false"}}}' -- sleep 1
#   forbidden: conflict: runtimeClass.scheduling.nodeSelector[runtime.example.com/sandbox] = true; pod.spec.nodeSelector[...] = false
```

## Lab 5 – Pod overhead
```bash
kubectl get pod sandboxed-pod -n runtimeclass-demo -o jsonpath='{.spec.overhead}{"\n"}'     # {"cpu":"250m","memory":"120Mi"}
kubectl describe node minikube | grep sandboxed-pod
#   runtimeclass-demo   sandboxed-pod   350m (4%)   350m (4%)   184Mi (0%)   184Mi (0%)
#                                       ^ 100m container + 250m overhead      ^ 64Mi + 120Mi
```
More in `../../scheduling-eviction/pod-overhead`.

---

## Useful commands
```bash
kubectl get runtimeclass
kubectl explain runtimeclass.scheduling
minikube ssh -- "sudo grep -A3 'runtimes\.' /etc/containerd/config.toml"
minikube ssh -- "sudo crictl inspectp <pod-id> | grep runtimeHandler"
```

## Cleanup
```bash
./cleanup.sh      # namespace, RuntimeClasses, node label, and removes the containerd handler
```
