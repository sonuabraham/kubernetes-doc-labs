# Check whether dockershim removal affects you – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/check-if-dockershim-removal-affects-you/

> Side by side: **`rt-lab`** (Docker Engine + cri-dockerd, [../start-rt-lab.sh](../start-rt-lab.sh)) and the default **`minikube`** cluster (containerd). Each check on the page is run on both nodes, so you can see what a Docker-dependent tool would lose. [../node.sh](../node.sh) runs node commands (`P=minikube` for the containerd node).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Building with Docker is fine** | Images are OCI images. They run on any runtime once they're pushed to a registry. |
| **What breaks** | Anything that talks to **dockerd on the node**: privileged Pods running `docker ps`/`exec`/`logs`, node scripts, SSH habits, agents mounting `docker.sock`, `/etc/docker/daemon.json` mirrors and registries (containerd has its own config), and alerting on Docker-specific names or log lines. |
| **Images** | An image built or pulled by `docker` on a node is **not** visible to containerd's CRI namespace (`k8s.io`), and the reverse is also true. |
| **cAdvisor metrics** | `/metrics/cadvisor` labels differ by runtime. Docker-era container names (`k8s_<container>_<pod>_<ns>_<uid>_<n>`) disappear, and some `container_fs_*` series are missing. Workaround: a standalone cAdvisor DaemonSet, or `/stats/summary`. |
| **Best practice** | Stop or inspect containers through the Kubernetes API, not the runtime CLI. |

---

## Step 0
```bash
cd tasks/administer-cluster/migrating-from-dockershim
./start-rt-lab.sh                 # if not running
cd check-if-dockershim-removal-affects-you
```

## Lab 1 – Docker commands on each node
```bash
../node.sh 'docker ps --format "{{.Names}}" | head -3'
#   k8s_storage-provisioner_storage-provisioner_kube-system_800a7dc5-..._1      <- k8s_<container>_<pod>_<ns>_<uid>_<restart>
#   k8s_coredns_coredns-559f6c778d-6vxr7_kube-system_c63c1e4d-..._0
#   k8s_POD_coredns-559f6c778d-6vxr7_kube-system_c63c1e4d-..._0                  <- the sandbox ("pause") container
P=minikube ../node.sh 'docker ps; systemctl is-active docker'
#   failed to connect to the docker API at unix:///var/run/docker.sock ... no such file or directory
#   inactive                                                                      <- a docker CLI exists, but no daemon
P=minikube ../node.sh 'crictl ps | head -3'             # the runtime-neutral replacement (CRI)
#   CONTAINER       IMAGE           STATE     NAME                  ATTEMPT   POD ID         POD                    NAMESPACE
#   70bfb6f46d8fa   6e38f40d628db   Running   storage-provisioner   2         df2f180054f15  storage-provisioner    kube-system
```

## Lab 2 – Docker-specific configuration to migrate
```bash
../node.sh 'cat /etc/docker/daemon.json'
#   {"exec-opts":["native.cgroupdriver=systemd"],"log-driver":"json-file","log-opts":{"max-size":"100m"},"storage-driver":"overlay2"}
```
Look for `registry-mirrors` and `insecure-registries` in this file. With containerd they belong in `/etc/containerd/certs.d/<registry>/hosts.toml`, and the cgroup driver becomes `SystemdCgroup = true` in `config.toml`. The containerd node has no `daemon.json`. Its settings are in `/etc/containerd/config.toml`:
```bash
P=minikube ../node.sh 'ls /etc/docker/daemon.json; grep -n "SystemdCgroup\|config_path" /etc/containerd/config.toml'
```

## Lab 3 – Pods that run Docker commands or mount the socket
The page's checklist step 1 (and the next page, [../migrating-telemetry-and-security-agents](../migrating-telemetry-and-security-agents/)): find Pods that mount `docker.sock`:
```bash
kubectl --context rt-lab get pods -A -o=jsonpath='{range .items[*]}{"\n"}{.metadata.namespace}{":\t"}{.metadata.name}{":\t"}{range .spec.volumes[*]}{.hostPath.path}{", "}{end}{end}' | sort | grep '/var/run/docker.sock'
#   (nothing yet - the next lab deploys such an agent)
```

## Lab 4 – cAdvisor metrics differ
```bash
for c in rt-lab minikube; do echo "== $c"
  kubectl --context $c get --raw /api/v1/nodes/$c/proxy/metrics/cadvisor | grep -E '^container_memory_working_set_bytes' \
    | grep -E 'docker-|cri-containerd-' | head -1 | grep -oE '(container|image|name|pod)="[^"]*"'; done
#   == rt-lab
#   container=""  image=""  name=""  pod=""           <- the kubelet's built-in cAdvisor can't identify Docker containers:
#                                                        per-container series lose their labels on a cri-dockerd node
#   == minikube
#   container="coredns"  image="registry.k8s.io/coredns/coredns:v1.14.6"  name="8d0ea901b35d..."  pod="coredns-...-fsjkx"
#                                                     <- containerd: name = container ID (the docs: "<container-id>")
for c in rt-lab minikube; do kubectl --context $c get --raw /api/v1/nodes/$c/proxy/metrics/cadvisor | grep -cE '^container_fs_'; done
```
Dashboards or alerts that key on `name=~"k8s_.*"` stop matching after a migration. Rewrite them to use `container`/`pod`/`namespace`. If you need the missing `container_fs_*` series, run cAdvisor as a DaemonSet or read the kubelet summary API instead:
```bash
kubectl --context minikube get --raw /api/v1/nodes/minikube/proxy/stats/summary | python3 -c 'import json,sys; p=json.load(sys.stdin)["pods"][0]; print(p["podRef"], p["containers"][0]["rootfs"])'
```

---

## Useful commands
```bash
kubectl get nodes -o wide                         # CONTAINER-RUNTIME
crictl ps | pods | images | logs <id>             # instead of docker ps / images / logs
kubectl get --raw /api/v1/nodes/<n>/proxy/metrics/cadvisor
kubectl get --raw /api/v1/nodes/<n>/proxy/stats/summary
```

## Cleanup
Nothing created. Keep `rt-lab` for the next labs.
