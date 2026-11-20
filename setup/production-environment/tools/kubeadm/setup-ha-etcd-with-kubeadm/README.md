# Set up a High Availability etcd Cluster with kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm/

> A real 3-member etcd cluster on machines **cp1, cp2, cp3** (HOST0–2 = 172.30.0.2/.4/.5) from [../machines.sh](../machines.sh),
> kubeadm v1.37.2, etcd **3.7.0**. Then the **external etcd** part of
> [../high-availability](../high-availability/) on a fourth machine (**w1**).
> - [step1-kubelet-for-etcd.sh](step1-kubelet-for-etcd.sh): step 1 verbatim + 2 marked changes
> - [steps2-4-on-host0.sh](steps2-4-on-host0.sh): steps 2–4 verbatim, variables filled in
> - [kubeadm-config-external-etcd.yaml](kubeadm-config-external-etcd.yaml): the HA page's external-etcd config, placeholders filled in
>   (+ marked lab additions)
>
> `scp`/`ssh` are replaced by `docker exec … tar` streams; the machines' `/tmp` is a tmpfs, which `docker cp` can't read.
>
> **Found:**
> - **Step 1 fails on a package install:** `bash: /etc/systemd/system/kubelet.service.d/kubelet.conf: No such file or directory` (and the
>   same for `20-etcd-service-manager.conf`). The kubeadm drop-in lives in `/usr/lib/systemd/system/kubelet.service.d/`;
>   `/etc/systemd/system/kubelet.service.d/` doesn't exist yet. Add `mkdir -p` first.
> - **Step 1 stores the KubeletConfiguration YAML as a systemd drop-in.** `kubelet.conf` sits in `kubelet.service.d/`, so systemd parses
>   it and logs `kubelet.conf:4: Assignment outside of section. Ignoring.` for each line. It works, but keep the YAML outside the drop-in
>   directory.
> - The page's kubelet config has no `failSwapOn: false`. On a host with swap this kubelet won't start (the lab machines see the host's swap).
> - **Step 8's command checks one member only.** `etcdctl … --endpoints https://${HOST0}:2379 endpoint health` prints a single line
>   (`https://172.30.0.2:2379 is healthy …`). The page's three-line sample needs `endpoint health --cluster`. `etcdctl` isn't on the hosts
>   (as the page expects). The etcd image has it, but no shell, so `ETCDCTL_API=3 etcdctl …` must be run as `etcdctl …` there (API v3 is
>   the default anyway).
> - **HA page, external etcd:** it copies `ca.crt` and `apiserver-etcd-client.crt/.key` to the control-plane node's **home directory**,
>   but its `kubeadm-config.yaml` reads them from `/etc/kubernetes/pki/etcd/ca.crt` and `/etc/kubernetes/pki/apiserver-etcd-client.*`.
>   The page never says to move them there.
> - (Lab pitfall) comment lines **before** a leading `---` make an empty first YAML document: kubeadm fails with
>   `kind and apiVersion is mandatory information that must be specified`.
> - After `kubeadm reset`, a machine that ran a CNI before is `Ready` right away on the next init: the old `10-kindnet.conflist` is still there.

## Key ideas (read first)

| Step | What happens |
|---|---|
| 1 kubelet as etcd service manager | a standalone kubelet (no API server, `staticPodPath`) on each etcd host |
| 2 one kubeadmcfg.yaml per host | `etcd.local.extraArgs`: `initial-cluster` lists all three, `initial-cluster-state: new`, per-host listen/advertise URLs |
| 3 CA | `kubeadm init phase certs etcd-ca` on HOST0 only; `ca.key` never leaves HOST0 |
| 4 member certs | server/peer/healthcheck-client/apiserver-etcd-client per host, generated on HOST0 with that host's SANs |
| 7 static Pods | `kubeadm init phase etcd local` writes `/etc/kubernetes/manifests/etcd.yaml` |
| External etcd control plane | `ClusterConfiguration.etcd.external` (endpoints + CA + client cert); kubeadm skips all etcd certs and the etcd static Pod |

## Lab 1 – The etcd cluster
```bash
cd setup/production-environment/tools/kubeadm/setup-ha-etcd-with-kubeadm
for m in cp1 cp2 cp3; do ../machines.sh x $m "$(cat step1-kubelet-for-etcd.sh)"; done
../machines.sh x cp1 'systemctl status kubelet'
#   Drop-In: /usr/lib/systemd/system/kubelet.service.d └─10-kubeadm.conf
#            /etc/systemd/system/kubelet.service.d └─20-etcd-service-manager.conf, kubelet.conf
#   Active: active (running)
#   journal: … kubelet.conf:4: Assignment outside of section. Ignoring.   (×n)

../machines.sh x cp1 "$(cat steps2-4-on-host0.sh)"          # configs + CA + all member certs on HOST0
../machines.sh x cp1 'find /tmp/172.30.0.* /etc/kubernetes/pki -type f | sort'
#   exactly the page's "complete list of required files": HOST0 keeps etcd/ca.key; /tmp/<HOST1|2>/pki has no ca.key
#   initial-cluster value: cp1=https://172.30.0.2:2380,cp2=https://172.30.0.4:2380,cp3=https://172.30.0.5:2380

# step 5 – copy (instead of scp): docker exec kadm-cp1 tar -C /tmp/<HOST> -cf - . | docker exec -i kadm-<host> tar -C /root -xf -
../machines.sh x cp2 'chown -R root:root pki; mv pki /etc/kubernetes/'       # (same on cp3) → kubeadmcfg.yaml + 9 files, no ca.key

# step 7
../machines.sh x cp1 'kubeadm init phase etcd local --config=/tmp/172.30.0.2/kubeadmcfg.yaml'
../machines.sh x cp2 'kubeadm init phase etcd local --config=$HOME/kubeadmcfg.yaml'      # (same on cp3)
#   [etcd] Creating static Pod manifest for local etcd in "/etc/kubernetes/manifests"

# step 8 (etcdctl inside the etcd container: crictl exec <etcd> etcdctl …)
etcdctl --cert /etc/kubernetes/pki/etcd/peer.crt --key /etc/kubernetes/pki/etcd/peer.key --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --endpoints https://172.30.0.2:2379 endpoint health
#   https://172.30.0.2:2379 is healthy: successfully committed proposal: took = 16.26455ms          <- one line
etcdctl … --endpoints https://172.30.0.2:2379 endpoint health --cluster
#   https://172.30.0.5:2379 is healthy … / https://172.30.0.2:2379 is healthy … / https://172.30.0.4:2379 is healthy …
etcdctl … member list -w table      # cp1, cp2, cp3 started, IS LEARNER false
```

## Lab 2 – A control plane on the external etcd (HA page, "External etcd nodes")
```bash
for m in cp1 cp2 cp3; do ../machines.sh x $m 'systemctl stop kubelet'; done   # inotify; the etcd containers keep running (CONTAINER_RUNNING)
# copy etcd/ca.crt + apiserver-etcd-client.crt/.key from cp1 to w1 – straight into /etc/kubernetes/pki/ (see Found)
docker cp kubeadm-config-external-etcd.yaml kadm-w1:/root/kubeadm-config.yaml
../machines.sh x w1 'kubeadm init --config kubeadm-config.yaml --upload-certs'
#   [init] Using Kubernetes version: v1.37.2            ("kubernetesVersion: stable")
#   [certs] External etcd mode: Skipping etcd/ca certificate authority generation   (… etcd/server, peer, healthcheck-client, apiserver-etcd-client)
#   Your Kubernetes control-plane has initialized successfully!
../machines.sh x w1 'ls /etc/kubernetes/manifests'    # kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml   (no etcd.yaml)
../machines.sh x w1 'grep -- --etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml'
#   - --etcd-servers=https://172.30.0.2:2379,https://172.30.0.4:2379,https://172.30.0.5:2379
kubectl create configmap stored-in-external-etcd --from-literal=x=1
etcdctl … --endpoints https://172.30.0.4:2379 get /registry/configmaps/default/stored-in-external-etcd --keys-only     # found on cp2
```
NOT from the docs – lose etcd members, keep the control plane:
```bash
# stop cp1's etcd (it was the leader):
kubectl create configmap one-member-down …   # error: … etcdserver: request timed out, possibly due to previous leader failure   (during the election)
# stop another member (cp3) instead, leader untouched:
kubectl create configmap one-follower-down … # configmap/one-follower-down created;   /readyz → ok
# two members down (cp1 + cp2):
kubectl create configmap two-members-down …  # error: … etcdserver: request timed out
kubectl get --raw '/readyz?verbose'          # [-]etcd failed  [-]etcd-readiness failed … readyz check failed
# systemctl start kubelet on the etcd hosts → static Pods back → /readyz ok
```

## Cleanup
```bash
../machines.sh x w1 'kubeadm reset -f'
for m in cp1 cp2 cp3; do ../machines.sh x $m 'kubeadm reset -f; rm -f /etc/systemd/system/kubelet.service.d/{kubelet.conf,20-etcd-service-manager.conf}; systemctl daemon-reload; systemctl stop kubelet'; done
# all machines: ../machines.sh down ; minikube start
```
