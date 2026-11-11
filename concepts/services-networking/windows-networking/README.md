# Networking on Windows – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/windows-networking/

> ⚠️ **Needs Windows nodes**, which minikube can't run. This lab shows the parts visible from Linux: how Windows workloads are targeted, the Windows section of kube-proxy's config, and which Service features apply. For real practice use a cloud cluster with a Windows node pool (AKS, EKS, GKE) or a kubeadm cluster with a Windows Server 2022 worker.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **HNS + HCN** | On Windows, the **Host Networking Service** and **Host Compute Network** create vSwitches, endpoints (vNICs), namespaces and policies (encapsulation, LB rules, ACLs, NAT), the job iptables does on Linux. |
| **Network modes** | **L2bridge** (attached to an external vSwitch, MAC rewritten), **L2Tunnel** (Azure only), **Overlay** (VXLAN, own subnet per network), **Transparent** (ovn-kubernetes). NAT isn't used in Kubernetes. |
| **CNI plugins** | win-bridge, win-overlay, azure-cni, Flannel (host-gw / VXLAN), Calico, OVN-Kubernetes… IPAM: host-local, azure-vnet-ipam, or Windows Server IPAM. |
| **Supported flows** | Pod↔Pod (IP/name), Pod→Service (ClusterIP, FQDN; PQDN only without dots), Pod→external, Node↔Pod. |
| **Service types** | NodePort, ClusterIP, LoadBalancer, ExternalName. |
| **Feature → OS build** | sessionAffinity ClientIP (WS2022), DSR (`--enable-dsr=true`, WS2019), Preserve-Destination, dual-stack (WS2019), client IP preservation (`externalTrafficPolicy: Local`, WS2019). |
| **DSR** | Direct Server Return: replies bypass the load balancer, which is faster and keeps client IPs. |
| **Limitations** | No host networking mode for pods; no NodePort access from the node itself; **> 64 backends** per Service unsupported; no IPv6 between pods on overlay; Local traffic policy only with DSR; outbound ICMP missing on some plugins. |
| **DNS** | No `ndots`. The search list is used only for single-label names (see `../dns-pod-service`). |

## The demo app
[00-windows-workload.yaml](00-windows-workload.yaml) is an IIS Deployment (`os.name: windows` + `nodeSelector kubernetes.io/os: windows`) and a NodePort Service using Windows-relevant options (`sessionAffinity: ClientIP`, `externalTrafficPolicy: Local`).

---

## Lab 1 – Windows pods never land on Linux nodes
```bash
cd concepts/services-networking/windows-networking
kubectl get nodes -L kubernetes.io/os                 # minikube   linux
kubectl apply -f 00-windows-workload.yaml ; sleep 5
kubectl get pods -n win-demo                          # Pending
kubectl get events -n win-demo --field-selector reason=FailedScheduling -o custom-columns=M:.message | head -2
#   0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector.
```
Without the nodeSelector the scheduler would place it on Linux, and the kubelet would reject it (`os.name` mismatch, see `../../workloads/pods`, Lab 5).

## Lab 2 – kube-proxy's Windows configuration
```bash
kubectl get cm kube-proxy -n kube-system -o jsonpath='{.data.config\.conf}' | grep -A6 winkernel
#   winkernel:
#     enableDSR: false              <- DSR off by default (a Windows kube-proxy would read this)
#     forwardHealthCheckVip: false
#     networkName: ""               <- the HNS network kube-proxy attaches to
#     rootHnsEndpointName: ""
#     sourceVip: ""                 <- needed in overlay mode
```
On a Windows node, kube-proxy runs in `kernelspace` mode and programs HNS load-balancer policies instead of iptables.

## Lab 3 – What you'd check on a real Windows node
```powershell
Get-HnsNetwork | Select Name, Type                 # l2bridge / overlay
Get-HnsEndpoint | Select IPAddress, IsRemoteEndpoint
Get-HnsPolicyList                                  # the Service load-balancer rules (the iptables equivalent)
```

---

## Cleanup
```bash
./cleanup.sh
```
