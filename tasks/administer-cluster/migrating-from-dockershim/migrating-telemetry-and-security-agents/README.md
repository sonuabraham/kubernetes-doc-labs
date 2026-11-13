# Migrating telemetry and security agents from dockershim – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/migrating-telemetry-and-security-agents/

> A toy "telemetry agent" DaemonSet of the old kind ([01-docker-agent.yaml](01-docker-agent.yaml)) mounts the node's `docker.sock` and runs `docker ps`. It's deployed on **`rt-lab`** (Docker Engine, [../start-rt-lab.sh](../start-rt-lab.sh)) and on **`minikube`** (containerd). [find-docker-sock.sh](find-docker-sock.sh) is the docs' detection script, verbatim. The vendor list on the docs page (Datadog, Dynatrace, Falco, …) links to each vendor's own migration notes; read them there.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Why agents talked to Docker** | Early agents got container lists, processes, logs and metrics from `docker ps/top/logs/stats`. Pod names came from the Kubernetes API. |
| **How to spot one** | The Pod mounts the Docker socket (`/var/run/docker.sock`) or its directory as a **hostPath** volume. |
| **After the switch** | Those calls fail. Migrate the agent to the CRI (`crictl`/CRI socket), the kubelet (`/stats/summary`, `/metrics/cadvisor`, `/pods`), or Kubernetes APIs. Newer agent versions usually support containerd. |
| **Silent failure trap** | A hostPath with no `type` **creates an empty directory** if the path is missing. The agent then starts fine and sees nothing. `type: Socket` turns that into a visible `FailedMount`. |

---

## Step 0
```bash
cd tasks/administer-cluster/migrating-from-dockershim
./start-rt-lab.sh                       # if not running
cd migrating-telemetry-and-security-agents
for c in rt-lab minikube; do kubectl --context $c apply -f 01-docker-agent.yaml; done
```

## Lab 1 – Find Pods that depend on dockerd
```bash
./find-docker-sock.sh --context rt-lab
#   agents-demo:	docker-agent-gcg4s:	/var/run/docker.sock, ,
./find-docker-sock.sh --context minikube
#   agents-demo:	docker-agent-hxw8f:	/var/run/docker.sock, ,
```
Drop the final `grep` in the script to review every hostPath mount (e.g. `/var/lib/docker/containers` for log shippers).

## Lab 2 – Same agent, two runtimes
```bash
kubectl --context rt-lab -n agents-demo logs ds/docker-agent --tail=2
#   10:04:26 containers seen: 16
#   k8s_coredns_coredns-559f6c778d-6vxr7_kube-system_c63c1e4d-..._0        <- parses Docker-era names
kubectl --context minikube -n agents-demo logs ds/docker-agent --tail=2
#   Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
#   10:04:27 containers seen: 0
kubectl --context minikube -n agents-demo get po
#   docker-agent-hxw8f   1/1   Running       <- "healthy", but blind
P=minikube ../node.sh 'ls -la /var/run/docker.sock'
#   drwxr-xr-x 2 root root 40 ... .          <- the kubelet created an empty DIRECTORY for the untyped hostPath
```

## Lab 3 – Make the failure visible: `type: Socket`
[02-docker-agent-socket-type.yaml](02-docker-agent-socket-type.yaml) is the same agent with `hostPath.type: Socket`:
```bash
kubectl --context minikube delete -f 01-docker-agent.yaml
P=minikube ../node.sh 'rmdir /var/run/docker.sock'       # remove the stray directory first
kubectl --context minikube apply -f 02-docker-agent-socket-type.yaml
kubectl --context minikube -n agents-demo get po
#   docker-agent-qvlbx   0/1   ContainerCreating
kubectl --context minikube -n agents-demo get events --field-selector reason=FailedMount -o custom-columns=MSG:.message
#   MountVolume.SetUp failed for volume "docker-sock" : hostPath type check failed, /var/run/docker.sock is not a
#   socket file, unable to determine its type: path "/var/run/docker.sock" does not exist
kubectl --context rt-lab apply -f 02-docker-agent-socket-type.yaml        # still fine where dockerd exists
```
Keep the agent on `rt-lab`. The [../change-runtime-containerd](../change-runtime-containerd/) lab shows it breaking during a real migration.

---

## Useful commands
```bash
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {range .spec.volumes[*]}{.hostPath.path} {end}{"\n"}{end}' | grep -i docker
crictl ps ; crictl stats ; crictl logs <id>               # CRI equivalents of docker ps / stats / logs
```

## Cleanup
```bash
./cleanup.sh       # both clusters (+ the stray directory on the containerd node)
```
