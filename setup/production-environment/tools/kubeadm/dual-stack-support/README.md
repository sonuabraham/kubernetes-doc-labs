# Dual-stack support with kubeadm – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/dual-stack-support/

> A real dual-stack kubeadm cluster: machines **ds1** (control plane) and **ds2** (worker) from [../machines.sh](../machines.sh) on a
> dual-stack Docker network (`NET=kubeadm-lab-net6 V4SUBNET=172.31.0.0/24 V6SUBNET=fd00:1:2:3::/64`). They got `172.31.0.2/fd00:1:2:3::2`
> and `.3/::3`, the same IPv6 prefix as the page's node-ip examples. minikube v1.39 can't do this
> ([tasks/network/validate-dual-stack](../../../../../tasks/network/validate-dual-stack/) could only show the Service side).
> - [docs-1.yaml](docs-1.yaml) … [docs-4.yaml](docs-4.yaml): the page's four config examples **verbatim**
> - [kubeadm-config-dual.yaml](kubeadm-config-dual.yaml): docs-1 + docs-2 with this lab's addresses (ranges unchanged) + swap tolerated
> - [kindnet-dual.yaml](kindnet-dual.yaml): [../kindnet.yaml](../kindnet.yaml) with `POD_SUBNET=10.244.0.0/16,2001:db8:42:0::/56`
>
> **Found:**
> - **The page's IPv6 Service range lies inside its IPv6 Pod range:** `2001:db8:42:1::/112` ⊂ `2001:db8:42:0::/56`. kubeadm accepts it
>   (`kubeadm config validate` → ok; `kubeadm init --dry-run` → no error). It still works because kube-controller-manager's node IPAM marks
>   the Service range as used. ds1 got `2001:db8:42::/64`, ds2 got `2001:db8:42:2::/64`, skipping `…:1::/64`. One /64 is wasted and the
>   layout is confusing. Non-overlapping ranges are clearer (e.g. Services in `2001:db8:43::/112`).
> - **The examples' node addresses don't fit together:** the control plane advertises `10.100.0.1` but sets `node-ip 10.100.0.2`; the
>   worker and the second control plane both use `10.100.0.2`. `advertiseAddress` and the first `node-ip` should be the node's own IP.
> - **Dual-stack Pod networking needs the CNI configured for both families.** With kindnet's `POD_SUBNET` IPv4-only, Pods still got IPv6
>   addresses from the node's `podCIDRs`, but IPv6 traffic to a Pod on the **other** node hung. With both ranges in `POD_SUBNET`,
>   kindnet installs `2001:db8:42:2::/64 via fd00:1:2:3::3`, and cross-node IPv6 works.
> - (Lab pitfall) the first copy of `../kindnet.yaml` had CRLF line endings (copied through `minikube ssh`, which adds `\r`), so `sed`
>   edits on `POD_SUBNET` silently matched nothing. Fixed in both files.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Prerequisite | `net.ipv6.conf.all.forwarding = 1` on every node (plus `net.ipv4.ip_forward`) |
| `podSubnet` / `serviceSubnet` | two comma-separated ranges, one per family; first family = primary |
| `node-ip` (kubeletExtraArgs) | `<IPv4>,<IPv6>` so the Node gets both InternalIPs |
| `advertiseAddress` | single address (the apiserver flag doesn't take two) |
| Node IPAM | per node a /24 (IPv4) and a /64 (IPv6) from the Pod ranges (`--node-cidr-mask-size-ipv4/-ipv6` defaults) |
| Services | `ipFamilyPolicy: SingleStack \| PreferDualStack \| RequireDualStack` |
| Single-stack | a cluster with one range per field still has the dual-stack feature available |

## Lab
```bash
cd setup/production-environment/tools/kubeadm
docker stop kadm-cp1 kadm-cp2 kadm-cp3 kadm-w1                    # inotify
NET=kubeadm-lab-net6 V4SUBNET=172.31.0.0/24 V6SUBNET=fd00:1:2:3::/64 ./machines.sh up ds1 ds2
docker exec kadm-ds1 ip -br addr show eth0       # 172.31.0.2/24 fd00:1:2:3::2/64 …
docker exec kadm-ds1 sysctl net.ipv6.conf.all.forwarding     # = 1   (docs' check)
#   + prepare-runtime.sh and install-kubeadm/install-debian.sh on both (NET=kubeadm-lab-net6 ./machines.sh x …)

# the docs' ranges:
./machines.sh x ds1 'kubeadm config validate --config docs-1.yaml'      # ok   (overlap not detected)
./machines.sh x ds1 'kubeadm init --pod-network-cidr=10.244.0.0/16,2001:db8:42:0::/56 --service-cidr=10.96.0.0/16,2001:db8:42:1::/112 --dry-run'   # no error

./machines.sh x ds1 'kubeadm init --config=kubeadm-config-dual.yaml'                          # initialized successfully
./machines.sh x ds1 'grep -oE -- "--(cluster-cidr|service-cluster-ip-range)=[^ ]*" /etc/kubernetes/manifests/kube-controller-manager.yaml'
#   --cluster-cidr=10.244.0.0/16,2001:db8:42:0::/56
#   --service-cluster-ip-range=10.96.0.0/16,2001:db8:42:1::/112
kubectl apply -f kindnet-dual.yaml
# ds2: JoinConfiguration as on the page (apiServerEndpoint 172.31.0.2:6443, real token/hash, node-ip "172.31.0.3,fd00:1:2:3::3")
./machines.sh x ds2 'kubeadm join --config=kubeadm-config.yaml'                               # This node has joined the cluster
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDRS:.spec.podCIDRs,IPS:.status.addresses[*].address
#   ds1   [10.244.0.0/24 2001:db8:42::/64]     172.31.0.2,fd00:1:2:3::2,ds1
#   ds2   [10.244.1.0/24 2001:db8:42:2::/64]   172.31.0.3,fd00:1:2:3::3,ds2        <- …:1::/64 skipped (Service range)
```
NOT from the docs – dual-stack workloads (see also [tasks/network/validate-dual-stack](../../../../../tasks/network/validate-dual-stack/)):
```bash
kubectl create deployment web --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --replicas=2 -- /agnhost netexec --http-port=8080
kubectl expose deployment web --port=80 --target-port=8080 --overrides='{"spec":{"ipFamilyPolicy":"RequireDualStack"}}'
kubectl get pods -l app=web -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IPS:.status.podIPs[*].ip
#   web-…-9hwmv   ds1   10.244.0.4,2001:db8:42::4
#   web-…-fg6wm   ds2   10.244.1.2,2001:db8:42:2::2
kubectl get svc web -o jsonpath='{.spec.clusterIPs} {.spec.ipFamilies}'     # ["10.96.34.69","2001:db8:42:1::f546"] ["IPv4","IPv6"]
# from a Pod on ds1:  wget http://[2001:db8:42:1::f546]/hostname ×6  → answers from both Pods
#                     wget http://[2001:db8:42:2::2]:8080/hostname   → web-…-fg6wm   (cross-node IPv6)
./machines.sh x ds1 'ip -6 route | grep 2001:db8:42:2'        # 2001:db8:42:2::/64 via fd00:1:2:3::3 dev eth0   (kindnet)
```

## Cleanup
```bash
docker rm -f kadm-ds1 kadm-ds2; docker volume rm kadm-ds1-var kadm-ds2-var; docker network rm kubeadm-lab-net6
# (./machines.sh down removes all lab machines and networks)
```
