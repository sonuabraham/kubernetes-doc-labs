# Creating a cluster with kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/

> A real two-node kubeadm cluster: control plane **cp1** + worker **w1**, both "machines" from [../machines.sh](../machines.sh) (kicbase
> containers on network `kubeadm-lab-net` 172.30.0.0/24). Packages come from pkgs.k8s.io as in [../install-kubeadm](../install-kubeadm/)
> (v1.37.2). NOT from the docs:
> - [../prepare-runtime.sh](../prepare-runtime.sh): the Container Runtimes page's containerd settings (`SystemdCgroup = true`, pause
>   `3.10.2`). kicbase's stock config has `SystemdCgroup = false`, `pause:3.6` and a podman CNI config.
> - [kubeadm-config.yaml](kubeadm-config.yaml): the page's `kubeadm init <args>` as a config file. `controlPlaneEndpoint: cluster-endpoint:6443`
>   (the page's recommendation, via `/etc/hosts` as in its example), `podSubnet 10.244.0.0/16`, and `failSwapOn: false` (the machines see
>   the host's swap).
> - [../kindnet.yaml](../kindnet.yaml): the Pod network add-on, kindnet exactly as minikube deploys it. The page leaves the choice to you,
>   and this one is already used by minikube here.
>
> **Found:**
> - **`admin.conf` from a workstation:** with `--control-plane-endpoint=cluster-endpoint`, admin.conf says `server: https://cluster-endpoint:6443`.
>   On the laptop: `Unable to connect to the server: dial tcp: lookup cluster-endpoint … server misbehaving`. The workstation must
>   resolve the name too; `--server https://172.30.0.2:6443` works because the IP is in the certificate's SANs.
> - `kubectl taint nodes --all node-role.kubernetes.io/control-plane-` prints `error: taint "node-role.kubernetes.io/control-plane" not found`
>   for every node without that taint (the worker), and exits non-zero. The page's sample shows only "untainted".
> - `kubeadm join` printed `[patches] Applied patch of type "application/strategic-merge-patch+json" to target "kubeletconfiguration"`:
>   kubeadm 1.37 patches the downloaded kubelet configuration for the joining node.
> - `kubeadm reset` leaves the CNI config (`/etc/cni/net.d/10-kindnet.conflist`) and iptables rules, as it says. `ipvsadm` isn't installed
>   (kube-proxy runs in iptables mode), so `ipvsadm -C` isn't needed.
> - Identical `product_uuid` on both machines (host value) caused no problem.

## Key ideas (read first)

| Step | What happens |
|---|---|
| `kubeadm init` | preflight → certs (`/etc/kubernetes/pki`) → kubeconfigs → static Pod manifests → wait for API → upload config → mark control plane (taint) → bootstrap token → CoreDNS + kube-proxy |
| `--control-plane-endpoint` | shared name/LB for all control-plane nodes; needed **from the start** if you ever want HA |
| Pod network add-on | without it nodes are `NotReady` and CoreDNS stays `Pending` |
| `admin.conf` / `super-admin.conf` | `O=kubeadm:cluster-admins` (bound to cluster-admin) / `O=system:masters` (bypasses RBAC: keep it offline) |
| `kubeadm join … --token … --discovery-token-ca-cert-hash` | mutual trust: the token authenticates the node, the hash pins the cluster CA |
| NodeRestriction | kubelets can't set `node-role.kubernetes.io/*` on themselves; label them with admin credentials |
| Tear down | drain → `kubeadm reset` → flush iptables/IPVS → `kubectl delete node` |

## Lab 1 – Control plane
```bash
cd setup/production-environment/tools/kubeadm
minikube stop
./machines.sh up cp1                                   # (install-kubeadm lab: already done)
./machines.sh x cp1 "$(cat prepare-runtime.sh)"       # SystemdCgroup = true, pause 3.10.2, podman CNI config removed
./machines.sh x cp1 "$(cat install-kubeadm/install-debian.sh)"
./machines.sh x cp1 'ip route show'                    # default via 172.30.0.1 dev eth0   <- kubeadm advertises 172.30.0.2
./machines.sh x cp1 'echo "172.30.0.2 cluster-endpoint" >> /etc/hosts'
docker cp create-cluster-kubeadm/kubeadm-config.yaml kadm-cp1:/root/
./machines.sh x cp1 'kubeadm init --config kubeadm-config.yaml'
#   [init] Using Kubernetes version: v1.37.2
#   [WARNING Swap]: … (tolerated)
#   [control-plane-check] kube-apiserver is healthy after 2.003620272s
#   Your Kubernetes control-plane has initialized successfully!
#   … kubeadm join cluster-endpoint:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --control-plane
#   … kubeadm join cluster-endpoint:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
#   (7 s – the images were already pulled by the install lab's preflight)
./machines.sh sh cp1
  export KUBECONFIG=/etc/kubernetes/admin.conf
  kubectl get nodes                          # cp1   NotReady   control-plane   v1.37.2
  kubectl get pods -A                        # coredns ×2 Pending; etcd, apiserver, controller-manager, scheduler, kube-proxy Running
  kubectl describe node cp1 | grep -E 'Taints|NetworkReady'
  #   Taints: node-role.kubernetes.io/control-plane:NoSchedule
  #   … container runtime network not ready: NetworkReady=false reason:NetworkPluginNotReady …
  openssl x509 -noout -subject <<< "$(kubectl config view --kubeconfig /etc/kubernetes/admin.conf --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d)"
  #   admin.conf:       subject=O = kubeadm:cluster-admins, CN = kubernetes-admin
  #   super-admin.conf: subject=O = system:masters, CN = kubernetes-super-admin
  kubectl get clusterrolebinding kubeadm:cluster-admins -o jsonpath='{.subjects} -> {.roleRef.name}'
  #   [{"kind":"Group","name":"kubeadm:cluster-admins",…}] -> cluster-admin
```

## Lab 2 – Pod network
```bash
docker cp kindnet.yaml kadm-cp1:/root/
./machines.sh x cp1 'KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f kindnet.yaml'
#   kindnet DaemonSet rolled out → cp1 Ready (41 s after init); coredns 10.244.0.2 / .3 Running; /etc/cni/net.d/10-kindnet.conflist
```

## Lab 3 – Worker node
```bash
./machines.sh up w1                                     # machine w1: 172.30.0.3
./machines.sh x w1 "$(cat prepare-runtime.sh)"; ./machines.sh x w1 "$(cat install-kubeadm/install-debian.sh)"
./machines.sh x w1 'echo "172.30.0.2 cluster-endpoint" >> /etc/hosts'
./machines.sh x cp1 'kubeadm token create --print-join-command'      # (or the line from init's output)
./machines.sh x w1 'kubeadm join cluster-endpoint:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --ignore-preflight-errors=Swap'
#   [patches] Applied patch of type "application/strategic-merge-patch+json" to target "kubeletconfiguration"
#   This node has joined the cluster: * Certificate signing request was sent to apiserver …
kubectl get nodes -o wide          # cp1 172.30.0.2 control-plane / w1 172.30.0.3 <none>, both Ready, containerd, Debian 12
```
NOT from the docs – workloads and isolation:
```bash
kubectl create deployment web --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --replicas=2 -- /agnhost netexec --http-port=8080
kubectl expose deployment web --port=80 --target-port=8080
kubectl get pods -l app=web -o wide                     # both on w1 (cp1 has the control-plane taint)
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
#   node/cp1 untainted
#   error: taint "node-role.kubernetes.io/control-plane" not found      <- for w1
kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-
kubectl scale deploy web --replicas=4                   # now 2 on cp1 (10.244.0.x), 2 on w1 (10.244.1.x)
# probe Pod on cp1: wget http://web.default/hostname ×6 → answers from all four Pods (cross-node Pod network works)
```

## Lab 4 – Managed node labels (NodeRestriction), with w1's own kubelet credentials
```bash
./machines.sh x w1 'kubectl --kubeconfig /etc/kubernetes/kubelet.conf auth whoami'    # system:node:w1, groups system:nodes
./machines.sh x w1 'kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node w1 node-role.kubernetes.io/worker='
#   Error from server (Forbidden): nodes "w1" is forbidden: is not allowed to modify labels: node-role.kubernetes.io/worker
./machines.sh x w1 'kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node w1 example.com/rack=r1'   # node/w1 labeled  (allowed)
./machines.sh x w1 'kubectl --kubeconfig /etc/kubernetes/kubelet.conf label node cp1 example.com/rack=r1'
#   … node 'w1' cannot read 'cp1', only its own Node object
kubectl label node w1 node-role.kubernetes.io/worker=   # with admin.conf: works → ROLES worker
```

## Lab 5 – From another machine (this laptop)
```bash
docker cp kadm-cp1:/etc/kubernetes/admin.conf ./admin.conf     # (docs: scp root@<control-plane-host>:/etc/kubernetes/admin.conf .)
kubectl --kubeconfig ./admin.conf get nodes
#   Unable to connect to the server: dial tcp: lookup cluster-endpoint on 127.0.0.53:53: server misbehaving
kubectl --kubeconfig ./admin.conf --server https://172.30.0.2:6443 get nodes      # cp1 / w1 Ready  (IP is in the apiserver cert SANs)
rm admin.conf                                                   # superuser credentials – don't leave copies around
```

## Lab 6 – Tear down
```bash
kubectl drain w1 --delete-emptydir-data --force --ignore-daemonsets      # pods evicted, node/w1 drained
./machines.sh x w1 'kubeadm reset -f'
#   [reset] Stopping the kubelet service … The reset process does not perform cleanup of CNI plugin configuration,
#   network filtering rules and kubeconfig files.
./machines.sh x w1 'iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X'   # (inside the machine's own netns)
./machines.sh x w1 'which ipvsadm'                       # not installed – kube-proxy used iptables mode
./machines.sh x w1 'ls /etc/cni/net.d'                   # 10-kindnet.conflist still there
kubectl delete node w1
./machines.sh x cp1 'kubeadm reset -f'                   # Deleted contents of the etcd data directory: /var/lib/etcd …
```

## Cleanup
```bash
./machines.sh down        # all lab machines, volumes, network
minikube start
```
(The next kubeadm labs reuse the machines, so this lab leaves them reset but running.)
