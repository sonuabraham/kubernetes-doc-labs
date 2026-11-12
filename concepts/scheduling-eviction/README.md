# Scheduling, Preemption and Eviction – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/scheduling-eviction/

## Multi-node without more minikube nodes
Scheduling needs several nodes, but this host can't start more minikube node containers: `fs.inotify.max_user_instances=128` is exhausted (a 2nd node's systemd fails with *"Failed to create control group inotify object: Too many open files"*). Raising it needs root (`sudo sysctl fs.inotify.max_user_instances=1024`).

Instead the labs use **fake nodes**, [fake-nodes.sh](fake-nodes.sh):
```bash
./fake-nodes.sh up 3       # Node objects fake-1..3 (labels type=fake, zone-a/b/c), 4 CPU / 8Gi, kept Ready by a heartbeat loop
./fake-nodes.sh down       # stop the heartbeat, delete the nodes
```
- The scheduler can't tell the difference, so filters, scores, spreading, taints and preemption all work on them.
- Pods bound to a fake node never start (no kubelet). Judge results by `spec.nodeName` and events, not `Running`.
- DaemonSets (kube-proxy, kindnet, CSI plugin) also create Pending Pods on them. That's harmless and goes away with `down`.
- Pods on fake nodes must be **force-deleted** (`./force-delete-on-fake.sh [ns]`), otherwise namespace deletion hangs; every lab cleanup does this.
- If the heartbeat stops, the node lifecycle controller marks them NotReady and taints them, which itself is useful for `../node-pressure-eviction`/taint labs.
