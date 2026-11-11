# Services, Load Balancing, and Networking – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/

> Sub-pages: [service](service/), [ingress](ingress/), [ingress-controllers](ingress-controllers/), [gateway-api](gateway-api/), [endpoint-slices](endpoint-slices/), [network-policies](network-policies/), [dns-pod-service](dns-pod-service/), [dual-stack](dual-stack/), [topology-aware-routing](topology-aware-routing/), [windows-networking](windows-networking/), [cluster-ip-allocation](cluster-ip-allocation/), [service-traffic-policy](service-traffic-policy/).

## Key ideas (read first)

| Piece of the network model | Who implements it |
|---|---|
| Every **Pod has its own cluster-wide IP**. Containers in a Pod share it and talk over `localhost`. | Runtime (CRI) creates the netns, CNI plugin assigns the IP |
| **Pod network**: every Pod reaches every Pod, on any node, **without NAT or proxies**. Node agents (kubelet…) reach the Pods on their node. | **CNI plugin** (minikube: **kindnet**) |
| **Service**: a stable IP/name in front of changing Pods. **EndpointSlices** track the current backends. | API + EndpointSlice controller; data plane by **kube-proxy** (or the CNI's own proxy) |
| **Gateway API / Ingress / `type: LoadBalancer`**: reach Services from outside. | Gateway/Ingress controllers, cloud LB |
| **NetworkPolicy**: allow/deny traffic between Pods. | The **CNI plugin**. Without support, the API exists but does **nothing**. |
| Treat Pods like VMs: own IP, any port, no host-port juggling or container links. | — |

## The demo app
[00-network-model.yaml](00-network-model.yaml) is namespace `netmodel-demo` with `server` (2 × agnhost netexec; `/clientip` echoes the caller's IP) + Service `server`, and a `client` pod.

---

## Lab 1 – Every Pod has its own IP
```bash
cd concepts/services-networking
kubectl apply -f 00-network-model.yaml
kubectl rollout status deploy/server -n netmodel-demo ; kubectl wait --for=condition=Ready pod/client -n netmodel-demo
kubectl get pods -n netmodel-demo -o custom-columns=NAME:.metadata.name,IP:.status.podIP
#   client 10.244.0.146   server-… 10.244.0.145   server-… 10.244.0.147     <- from the node's pod CIDR 10.244.0.0/24
```

## Lab 2 – Pod to Pod without NAT
```bash
S=$(kubectl get pod -n netmodel-demo -l app=server -o jsonpath='{.items[0].status.podIP}')
kubectl exec client -n netmodel-demo -- wget -qO- http://$S:8080/clientip ; echo
#   10.244.0.146:36612        <- the server sees the CLIENT POD'S OWN IP: no NAT in between
kubectl exec client -n netmodel-demo -- wget -qO- http://server/clientip ; echo
#   10.244.0.146:47958        <- also through the Service (kube-proxy DNATs the destination, not the source)
```

## Lab 3 – Node agents can reach Pods
```bash
minikube ssh -- "curl -s http://$S:8080/hostname"        # server-…  (what the kubelet does for HTTP probes)
```

## Lab 4 – A stable Service in front of changing Pods
```bash
kubectl get svc server -n netmodel-demo -o jsonpath='{.spec.clusterIP}{"\n"}'          # 10.105.46.98
kubectl delete pod -n netmodel-demo -l app=server ; kubectl rollout status deploy/server -n netmodel-demo
kubectl get pods -n netmodel-demo -l app=server -o custom-columns=IP:.status.podIP   # NEW pod IPs
kubectl get svc server -n netmodel-demo -o jsonpath='{.spec.clusterIP}{"\n"}'          # same 10.105.46.98
kubectl get endpointslices -n netmodel-demo -l kubernetes.io/service-name=server -o jsonpath='{.items[0].endpoints[*].addresses}{"\n"}'   # the new IPs
```

## Lab 5 – Who implements what on minikube
```bash
minikube ssh -- ls /etc/cni/net.d                      # 10-kindnet.conflist (the others are disabled by minikube)
minikube ssh -- "sudo cat /etc/cni/net.d/10-kindnet.conflist" | head -15
#   "type": "ptp", "ipMasq": false, ipam host-local subnet 10.244.0.0/24     <- CNI plugin config
kubectl get ds -n kube-system                          # kindnet (pod network) + kube-proxy (Service data plane)
kubectl get cm kube-proxy -n kube-system -o jsonpath='{.data.config\.conf}' | grep ^mode    # iptables
```

---

## Cleanup
```bash
./cleanup.sh
```
