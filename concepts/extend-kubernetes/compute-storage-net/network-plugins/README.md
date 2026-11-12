# Network Plugins – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/

> The docs' snippets are **verbatim**: [calico-portmap.conflist](calico-portmap.conflist) (hostPort via `portmap`), [calico-bandwidth.conflist](calico-bandwidth.conflist) (traffic shaping via `bandwidth`) and [bandwidth-annotations-excerpt.yaml](bandwidth-annotations-excerpt.yaml). This cluster runs **kindnet**, not Calico, so the lab applies the same two ideas to kindnet's real chain.
>
> The demo files:
> - [00-demo.yaml](00-demo.yaml) (namespace `cni-demo`): two file servers, one carrying the docs' annotations; a client; a `hostPort` Pod.
> - [timeit.sh](timeit.sh): times downloads.
> - [bandwidth.sh](bandwidth.sh) `on|off`: adds or removes the bandwidth plugin on the node, with a backup.
> - [cni-by-hand.sh](cni-by-hand.sh): runs CNI plugins by hand, like a container runtime does.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **CNI** | Container Network Interface: a spec plus **executables**. The runtime runs a plugin with `CNI_COMMAND=ADD/DEL/CHECK/VERSION` in env vars and the network config JSON on stdin. The plugin answers with a JSON result. |
| **Who calls it** | The **container runtime** (containerd/CRI-O), configured with `conf_dir` (`/etc/cni/net.d`) and `bin_dir` (`/opt/cni/bin`). The kubelet's `--network-plugin`/`--cni-bin-dir` were **removed in 1.24**. |
| **Spec versions** | Use a plugin supporting CNI **v0.4.0 or later**. **v1.0.0** is recommended. |
| **Requirements** | A **loopback** `lo` in every sandbox, **hostPort** support (`portmap` plugin, `capabilities.portMappings`), and optional **traffic shaping** (`bandwidth` plugin, `capabilities.bandwidth`). |
| **Chains (`.conflist`)** | `plugins: [...]` run in order. The main plugin creates the interface and IP, then **meta plugins** (portmap, bandwidth, tuning, firewall) adjust things. |
| **Capabilities** | Runtime-supplied args. The kubelet passes Pod `hostPort`s and the `kubernetes.io/ingress-bandwidth`/`egress-bandwidth` annotations, and only plugins that declare the capability receive them. |
| **Experimental shaping** | With no `bandwidth` plugin in the chain, the annotations are **silently ignored**. |

---

## Lab 1 – What the node is configured with
```bash
cd concepts/extend-kubernetes/compute-storage-net/network-plugins
minikube ssh -- 'ls /etc/cni/net.d/; sudo cat /etc/cni/net.d/10-kindnet.conflist; ls /opt/cni/bin'
#   10-crio-bridge.conflist.disabled.mk_disabled  10-kindnet.conflist  87-podman-bridge.conflist.mk_disabled
#   "cniVersion": "0.3.1", "name": "kindnet", "plugins": [ {"type": "ptp", "ipam": {"type": "host-local", ... "10.244.0.0/24"}},
#                                                          {"type": "portmap", "capabilities": {"portMappings": true}} ]
#   bandwidth bridge dhcp dummy firewall host-device host-local ipvlan loopback macvlan portmap ptp sbr static tap tuning vlan vrf
minikube ssh -- 'sudo grep -A2 "cri\".cni\]" /etc/containerd/config.toml'
#   bin_dir = "/opt/cni/bin"   conf_dir = "/etc/cni/net.d"        <- the runtime owns CNI, not the kubelet
minikube ssh -- 'echo "{}" | sudo CNI_COMMAND=VERSION /opt/cni/bin/portmap'
#   {"cniVersion":"1.1.0","supportedVersions":["0.1.0","0.2.0","0.3.0","0.3.1","0.4.0","1.0.0","1.1.0"]}
```
Findings:
- kindnet's conflist declares **`cniVersion: 0.3.1`**, which is older than the page's v0.4.0 minimum. The plugin binaries support up to 1.1.0.
- The chain has `portmap`, so hostPort works. `bandwidth` is installed but **not in the chain**.
- minikube disabled the other configs by renaming them. The runtime only loads `.conf`, `.conflist` and `.json` files.

## Lab 2 – Loopback, the main plugin, and IPAM
```bash
kubectl apply -f 00-demo.yaml && kubectl wait --for=condition=Ready pod --all -n cni-demo --timeout=120s
kubectl exec client -n cni-demo -- ip -o addr
#   1: lo    inet 127.0.0.1/8             <- loopback, required in every sandbox
#   2: eth0  inet 10.244.0.158/24         <- ptp plugin (veth pair), IP from host-local IPAM
minikube ssh -- 'sudo ip netns list | head -3'             # cni-ee3c9843-...  one netns per Pod sandbox
minikube ssh -- 'sudo cat /run/cni-ipam-state/kindnet/10.244.0.158'
#   f040e0e00c16...   eth0                <- host-local's bookkeeping: IP -> sandbox ID + interface
```

## Lab 3 – hostPort through `portmap`
```bash
curl -s http://$(minikube ip):8088/                          # hello-from-hostport
minikube ssh -- 'sudo iptables -t nat -S CNI-HOSTPORT-DNAT'
#   -A CNI-HOSTPORT-DNAT ... --comment "dnat name: \"kindnet\" id: \"50ee948a...\"" -m multiport --dports 8088 -j CNI-DN-b343d...
```
`portmap` got `portMappings` from the runtime (the Pod's `hostPort: 8088`) and wrote the DNAT rules. Without that capability in the chain, `hostPort` silently does nothing.

## Lab 4 – Traffic shaping: annotations do nothing until `bandwidth` is in the chain
```bash
./timeit.sh 2
#   server-free     2 MB in   0.17s  =   92.46 Mbit/s
#   server-limited  2 MB in   0.18s  =   89.19 Mbit/s      <- docs' 1M annotations ignored (the times include kubectl exec overhead)
./bandwidth.sh on                                            # chain: ['ptp', 'portmap', 'bandwidth']
kubectl delete pod server-limited server-free -n cni-demo ; kubectl apply -f 00-demo.yaml     # CNI runs only at sandbox creation
kubectl wait --for=condition=Ready pod --all -n cni-demo --timeout=120s
minikube ssh -- 'sudo tc qdisc show | grep tbf'
#   qdisc tbf 1: dev vethd296bf58 root ... rate 1Mbit burst 21474835b      <- egress
#   qdisc tbf 1: dev bwpa5ca7ccdcbd5 root ... rate 1Mbit burst 21474835b   <- ingress (via an ifb device)
./timeit.sh 24
#   server-free     24 MB in   0.24s  =  809.46 Mbit/s
#   server-limited  24 MB in  39.03s  =    4.92 Mbit/s      <- the first ~21 MB ride the burst, then 1 Mbit/s
./timeit.sh 2
#   server-limited  2 MB in  16.80s  =    0.95 Mbit/s       <- bucket empty: exactly the 1M annotation
./bandwidth.sh off                                           # restore kindnet's original chain
```
The token bucket's **burst is huge** (21,474,835 bytes ≈ 20 MiB), so short transfers look unshaped. Test with more data than the burst.

## Lab 5 – Be the container runtime: run CNI by hand
```bash
./cni-by-hand.sh
#   == a fresh netns has only a DOWN loopback
#       lo: DOWN
#   == CNI_COMMAND=ADD  loopback
#   {"cniVersion":"1.0.0","interfaces":[{"name":"lo",...}],"ips":[{"address":"127.0.0.1/8"...}]}
#   == CNI_COMMAND=ADD  bridge (+ host-local IPAM)
#       cniVersion: 1.0.0 ips: ['10.99.0.2/24'] interfaces: ['cni-hand0', 'veth1084564f', 'eth0']
#   == inside the netns now
#       lo 127.0.0.1/8
#       eth0 10.99.0.2/24
#       64 bytes from 10.99.0.1: icmp_seq=1 ttl=64 time=0.067 ms
#   == IPAM bookkeeping (host-local): one file per allocated IP, containing the container ID
#       10.99.0.2 -> hand-1
#   == CNI_COMMAND=CHECK without prevResult, then with it
#       {"code": 999, "msg": "Required prevResult missing"}
#       exit 0: network is as ADD left it
#   == CNI_COMMAND=DEL
#       IP released (only last_reserved_ip.0 lock left)
```
That's the whole contract: env vars, config on stdin, result on stdout, and errors as JSON with a `code`. The runtime caches ADD's result so it can pass it as `prevResult` to CHECK and DEL. The script uses its own bridge and subnet and removes everything afterwards.

---

## Useful commands
```bash
minikube ssh -- 'ls /etc/cni/net.d /opt/cni/bin'
minikube ssh -- 'sudo iptables -t nat -S CNI-HOSTPORT-DNAT ; sudo tc qdisc show'
kubectl get pods -n kube-system -l app=kindnet
```

## Notes from testing
- A second minikube profile (`cni-lab`) couldn't be used: with two clusters running, kube-proxy failed with `fsnotify watcher init: too many open files` (host `fs.inotify.max_user_instances=128`), and kindnet never wrote its conflist. That's why Lab 4 edits the main node, with a backup at `/var/lib/minikube/10-kindnet.conflist.orig`. kindnet hadn't rewritten its conflist since node start, so the edit stuck.

## Cleanup
```bash
./cleanup.sh        # deletes cni-demo; restores kindnet's conflist if bandwidth.sh on was left active
```
