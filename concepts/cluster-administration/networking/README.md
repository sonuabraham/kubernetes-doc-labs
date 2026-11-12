# Cluster Networking – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/networking/

> A concepts page with no YAML. [show-ranges.sh](show-ranges.sh) (read-only) shows the three address ranges and the CNI plugin implementing them on this minikube. The network model itself (Pod-to-Pod, Services) is exercised in `../../services-networking` and its sub-labs.

## Key ideas (read first)

| Range | Configured by | Who allocates |
|---|---|---|
| **Pod IPs** | `--cluster-cidr` (controller-manager) + the CNI plugin | Node IPAM controller gives each node a `podCIDR`, and the CNI's IPAM (here `host-local`) picks Pod IPs from it |
| **Service ClusterIPs** | `--service-cluster-ip-range` (API server) → `ServiceCIDR` objects | API server, tracked as `IPAddress` objects (see `../../services-networking/cluster-ip-allocation`) |
| **Node IPs** | The infrastructure (VM or host network) | – |
| **IP families** | IPv4, IPv6 or dual-stack: both CIDRs per family (see `../../services-networking/dual-stack`) | |
| **Implementing the model** | A CNI plugin (kindnet, Calico, Cilium, Flannel…) must give every Pod a routable IP, with no NAT between Pods. | |

---

## Lab – Read the ranges
```bash
cd concepts/cluster-administration/networking
./show-ranges.sh
```
Measured:
```
--cluster-cidr=10.244.0.0/16  --allocate-node-cidrs=true
NODE      PODCIDRS          INTERNAL-IP
minikube  ["10.244.0.0/24"] 192.168.58.2
--service-cluster-ip-range=10.96.0.0/12
servicecidr/kubernetes  10.96.0.0/12
ipaddress 10.105.227.54  → services/kube-system/metrics-server   ...
/etc/cni/net.d: 10-kindnet.conflist (active), 10-crio-bridge…mk_disabled, 87-podman-bridge…mk_disabled
routes: 10.244.0.x dev vethXXXX scope host        <- one /32 route per Pod (kindnet ptp plugin)
```
kindnet's config is `ptp` + `host-local` IPAM with `"subnet": "10.244.0.0/24"`: point-to-point veth pairs and per-Pod host routes, no bridge. With more nodes, every node gets its own /24, and adding two fake nodes (`../../scheduling-eviction/fake-nodes.sh up 2`) shows it immediately:
```
NODE      PODCIDR
fake-1    10.244.1.0/24
fake-2    10.244.2.0/24
minikube  10.244.0.0/24
```
The three ranges must not overlap each other or the node network (192.168.58.0/24 here).

---

## Useful commands
```bash
kubectl get nodes -o custom-columns=NODE:.metadata.name,PODCIDRS:.spec.podCIDRs
kubectl get servicecidrs,ipaddresses
kubectl get pods -A -o wide | awk '{print $7}' | sort -t. -k3,3n | head
```

## Cleanup
Nothing to clean up (the fake nodes are removed with `fake-nodes.sh down`).
