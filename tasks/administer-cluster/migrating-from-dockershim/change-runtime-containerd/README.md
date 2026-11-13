# Changing the Container Runtime on a Node from Docker Engine to containerd – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/change-runtime-containerd/

> A **real migration** of the throwaway node **`rt-lab`** ([../start-rt-lab.sh](../start-rt-lab.sh)) from Docker Engine (+ cri-dockerd) to containerd, in the page's order:
>
> drain → stop kubelet and Docker → configure containerd → point the kubelet at containerd → start → verify → remove Docker → uncordon
>
> It's a single node, so the control plane goes down for a minute too. [../node.sh](../node.sh) runs node commands as root.
>
> **Run this lab last in the folder.** Afterwards rt-lab no longer has Docker. Recreate it with `minikube delete -p rt-lab && ../start-rt-lab.sh`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Same containerd** | Docker Engine already runs on containerd (`containerd.io` package). The migration changes **who talks to it**: the kubelet, through containerd's built-in CRI plugin, instead of dockerd/cri-dockerd. |
| **Kubelet endpoint** | `--container-runtime-endpoint=unix:///run/containerd/containerd.sock`. kubeadm keeps the node's socket in `/var/lib/kubelet/instance-config.yaml` (`containerRuntimeEndpoint`). Here the live setting is in `config.yaml` too, because minikube's kubelet ignores `kubeadm-flags.env` (see [../../kubeadm/kubeadm-reconfigure](../../kubeadm/kubeadm-reconfigure/)). |
| **cgroup driver** | `containerd config default` has `SystemdCgroup = false`. Current kubelets **take the driver from the CRI runtime**, so they'd silently switch to `cgroupfs`. Set `SystemdCgroup = true` on systemd hosts. |
| **Lost on the way** | Images that only exist in Docker's store (`docker build`, `docker pull`), every Docker-based tool or agent, and bare Pods evicted by the drain. |
| **Remove Docker carefully** | Purge `docker-ce docker-ce-cli` only. **Not** `containerd.io`, which is now your runtime. `/var/lib/docker` stays behind. |

---

## Step 0 – the "before" picture
```bash
cd tasks/administer-cluster/migrating-from-dockershim
./start-rt-lab.sh                           # if needed
cd change-runtime-containerd
K="kubectl --context rt-lab"
../node.sh 'dpkg -l | grep -E "docker-ce|containerd" | awk "{print \$2, \$3}"'
#   containerd.io 2.3.4-1~debian.12~bookworm
#   docker-ce 5:29.7.2-1~debian.12~bookworm   docker-ce-cli 5:29.7.2-...
# an image that only exists in Docker's image store:
../node.sh 'mkdir -p /root/hello && cd /root/hello && printf "FROM busybox:1.36\nCMD [\"sh\",\"-c\",\"while true; do echo hello from a docker-built image; sleep 30; done\"]\n" > Dockerfile && docker build -q -t local/hello:1 .'
$K create ns runtime-demo
$K -n runtime-demo run hello --image=local/hello:1 --image-pull-policy=Never
$K -n runtime-demo create deploy web --image=nginx --replicas=2
$K -n runtime-demo logs hello                       # hello from a docker-built image
$K apply -f ../migrating-telemetry-and-security-agents/02-docker-agent-socket-type.yaml     # a docker.sock "agent"
$K get nodes -o wide                                # CONTAINER-RUNTIME docker://29.7.2
```

## Lab 1 – Drain
```bash
$K drain rt-lab --ignore-daemonsets
#   cannot delete Pods that declare no controller (use --force to override): kube-system/storage-provisioner, runtime-demo/hello
$K drain rt-lab --ignore-daemonsets --force
#   pod/storage-provisioner evicted   pod/coredns-... evicted   pod/hello evicted   node/rt-lab drained
```

## Lab 2 – Stop the kubelet and Docker
```bash
../node.sh 'systemctl stop kubelet; systemctl disable docker.service --now'
#   Removed "/etc/systemd/system/multi-user.target.wants/docker.service".
#   Warning: Stopping docker.service, but it can still be activated by:
#     docker.socket                           <- the docs' two commands leave socket activation on
../node.sh 'systemctl disable --now docker.socket cri-docker.socket cri-docker.service; systemctl is-active docker docker.socket cri-docker'
#   inactive inactive inactive
```

## Lab 3 – Configure containerd
```bash
../node.sh 'cp /etc/containerd/config.toml /root/containerd-config.minikube.toml
  containerd config default > /etc/containerd/config.toml          # the docs: containerd config default | sudo tee ...
  head -1 /etc/containerd/config.toml; grep -nE "SystemdCgroup|sandbox =|conf_dir|bin_dirs" /etc/containerd/config.toml
  systemctl restart containerd'
#   version = 4                                        <- containerd 2.x config format
#   28:      sandbox = 'registry.k8s.io/pause:3.10.2'
#   90:            SystemdCgroup = false              <- remember this one
#   94:      bin_dirs = ['/opt/cni/bin']
#   95:      conf_dir = '/etc/cni/net.d'               <- same CNI config as before: Pod networking carries over
```

## Lab 4 – Point the kubelet at containerd and start it
```bash
../node.sh 'cd /var/lib/kubelet; cp config.yaml /root/; cp instance-config.yaml /root/
  sed -i "s|unix:///var/run/cri-dockerd.sock|unix:///run/containerd/containerd.sock|" config.yaml instance-config.yaml
  grep -H containerRuntimeEndpoint config.yaml instance-config.yaml
  systemctl start kubelet; sleep 20
  journalctl -u kubelet --since "-25s" | grep -o "Using cgroup driver setting received from the CRI runtime.*"'
#   config.yaml:containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
#   instance-config.yaml:containerRuntimeEndpoint: "unix:///run/containerd/containerd.sock"
#   Using cgroup driver setting received from the CRI runtime" cgroupDriver="cgroupfs"     <- overrides cgroupDriver: systemd!
```
It works, but with two cgroup managers on a systemd host. Fix containerd as the containerd guide says:
```bash
../node.sh 'sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml
  systemctl restart containerd; systemctl restart kubelet; sleep 15
  journalctl -u kubelet --since "-20s" | grep -o "Using cgroup driver setting received from the CRI runtime.*"'
#   ... cgroupDriver="systemd"
```

## Lab 5 – Verify the node
```bash
until $K get --raw /readyz >/dev/null 2>&1; do sleep 3; done      # static Pods are recreated under containerd (images re-pulled)
$K get nodes -o wide
#   rt-lab   Ready,SchedulingDisabled   v1.37.0   ...   containerd://2.3.4     (briefly still docker://... until the kubelet re-reports)
../node.sh 'crictl ps | head -4'
```

## Lab 6 – Remove Docker Engine, uncordon
```bash
../node.sh 'apt-get purge -y docker-ce docker-ce-cli | grep -E "^Removing|^Purging"
  dpkg -l | grep -E "containerd|docker" | awk "{print \$2}"; systemctl is-active containerd; ls /var/lib/docker'
#   Removing docker-ce ...  Removing docker-ce-cli ...
#   containerd.io   docker-buildx-plugin     <- containerd kept (the docs' caution)
#   active
#   buildkit containers engine-id ...       <- Docker's data is still on disk; delete it yourself if wanted
$K uncordon rt-lab
```

## Lab 7 – What didn't survive
```bash
$K -n runtime-demo run hello --image=local/hello:1 --image-pull-policy=Never     # the drain deleted the bare Pod
$K get po -A
#   runtime-demo   web-...     1/1   Running             <- registry images: fine
#   runtime-demo   hello       0/1   ErrImageNeverPull   <- docker-built image isn't in containerd's k8s.io namespace
#   agents-demo    docker-agent-...   1/1   Running      <- "Running", yet:
$K -n agents-demo logs ds/docker-agent --tail=1
#   Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?
../node.sh 'ls -la /var/run/docker.sock'
#   srw-rw---- 1 root docker 0 ... /var/run/docker.sock     <- stale socket file, nothing listening:
#                                                               even hostPath type: Socket can't catch that
```
To fix the image, push it to a registry, or import it into containerd: `docker save` before the migration, then `ctr -n k8s.io images import`. `storage-provisioner` (a bare Pod) is gone too.

---

## Useful commands
```bash
kubectl get nodes -o wide
crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps | images | info
containerd config default ; containerd config dump | grep SystemdCgroup
ctr -n k8s.io images ls ; ctr -n k8s.io images import <tar>
```

## Cleanup
```bash
minikube delete -p rt-lab          # the node is migrated; ../start-rt-lab.sh recreates a Docker one
```
