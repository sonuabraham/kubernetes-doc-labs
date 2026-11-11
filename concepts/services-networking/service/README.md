# Kubernetes Services – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/service/
(and the linked https://kubernetes.io/docs/reference/networking/virtual-ips/)

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Why Services** | Pods come and go and change IPs. A Service gives a stable name + virtual IP in front of a changing set of pods. |
| `spec.selector` | Pods whose labels match become the backends. Kubernetes keeps **EndpointSlices** updated with their IPs. |
| `port` / `targetPort` | `port` = what clients hit on the Service. `targetPort` = port on the pod (number **or** container port name). Defaults to `port`. |
| `protocol` | `TCP` (default), `UDP`, `SCTP`. |
| **Multi-port** | More than one port → **every** port needs a `name`. |
| **No selector** | Kubernetes creates no EndpointSlices. You write them yourself (external DB, other cluster, migration). |
| **EndpointSlices** | Stable since v1.21. Up to 100 endpoints per slice by default. The old `Endpoints` API is deprecated since v1.33 (1000 cap, no dual-stack). |
| `appProtocol` | A hint for implementations, e.g. `http`, `kubernetes.io/h2c`, `kubernetes.io/ws`, `kubernetes.io/wss`. |
| **kube-proxy** | Runs on every node and programs iptables/nftables/IPVS so traffic to `clusterIP:port` goes to a backend pod. |

### Service types

| Type | What you get | Builds on |
|---|---|---|
| `ClusterIP` (default) | Virtual IP reachable only inside the cluster | – |
| `NodePort` | `<every-node-ip>:<30000-32767>` | ClusterIP |
| `LoadBalancer` | External LB from a cloud provider or controller | NodePort + ClusterIP |
| `ExternalName` | A DNS CNAME to an outside name. No proxying. | – |
| *Headless* (`clusterIP: None`) | No VIP. DNS returns the pod IPs directly. | – |

**Note:** Ingress and Gateway API are **not** Service types. They route HTTP(S) into Services.

## The demo app

```
namespace svc-demo
 ┌────────┐   curl my-service/hostname   ┌──────────────── Service ─────────────────┐
 │ client │ ───────────────────────────▶ │ my-service:80  →  targetPort 9376        │
 └────────┘                              └───────┬──────────────┬──────────────┬────┘
 (netshoot: curl, dig, nc)                       ▼              ▼              ▼
                                            web-xxx-a      web-xxx-b      web-xxx-c
                                         label app.kubernetes.io/name=MyApp
                                         agnhost netexec: HTTP 9376, UDP 9377
```

`GET /hostname` on a web pod returns **its pod name**, so you can see which backend answered.
`./test.sh <url> [count]` sends `count` requests from `client` and counts the answers per pod.

---

## Step 0 – Cluster

```bash
# 2 nodes, so Lab 11 (traffic policies) shows a real difference
minikube start --nodes=2
# A single node (your existing cluster) works for every lab except 11.
```

## Step 1 – Deploy the app

```bash
cd service
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Ready pod --all -n svc-demo --timeout=180s
kubectl get pods -n svc-demo -o wide --show-labels
```

## Lab 1 – ClusterIP (the default)
```bash
kubectl apply -f 01-clusterip.yaml
kubectl get svc my-service -n svc-demo                 # note CLUSTER-IP
kubectl get endpointslices -n svc-demo -l kubernetes.io/service-name=my-service -o wide
./test.sh http://my-service/hostname
```
Expected: answers spread across the 3 `web-…` pods. The EndpointSlice lists the 3 pod IPs on port 9376.

Watch EndpointSlices follow the pods:
```bash
kubectl scale deploy web -n svc-demo --replicas=5
kubectl get endpointslices -n svc-demo -l kubernetes.io/service-name=my-service
./test.sh http://my-service/hostname 20                # now 5 different pods
kubectl scale deploy web -n svc-demo --replicas=3
```
Try: `kubectl get pods -n svc-demo -o wide` shows the pod IPs changing as you scale. The Service IP stays the same.

## Lab 2 – targetPort by name
```bash
kubectl apply -f 02-named-port.yaml
kubectl wait --for=condition=Ready pod/nginx -n svc-demo
kubectl exec -n svc-demo client -- curl -s nginx-service | head -4
kubectl describe svc nginx-service -n svc-demo          # TargetPort: http-web-svc/TCP
```
Expected: the nginx welcome page. The Service resolves `http-web-svc` to port 80 on each pod.
Why it helps: different pods can expose the same port name on different numbers, and you can change the number without editing the Service.

## Lab 3 – Multi-port (and mixed TCP/UDP)
```bash
kubectl apply -f 03-multi-port.yaml
./test.sh http://my-multi-port/hostname 6
kubectl exec -n svc-demo client -- sh -c 'echo hostname | nc -u -w2 my-multi-port 9377'
```
Expected: HTTP on port 80 and UDP on port 9377 both answer with a pod name.
Experiment: delete one `name:` line and re-apply. The API server rejects it because every port needs a name when there is more than one.

## Lab 4 – Discovering Services: env vars and DNS
### Environment variables
```bash
kubectl exec -n svc-demo client -- sh -c 'env | grep MY_SERVICE'        # nothing!
kubectl apply -f 04-client-after-service.yaml
kubectl wait --for=condition=Ready pod/client-late -n svc-demo
kubectl exec -n svc-demo client-late -- sh -c 'env | grep MY_SERVICE | sort'
```
Expected: `client` (created before the Service) has **no** variables. `client-late` has `MY_SERVICE_SERVICE_HOST`, `MY_SERVICE_SERVICE_PORT`, `MY_SERVICE_PORT_80_TCP…`, and so on.
**Lesson:** env vars are set only at pod start, so the Service must exist first. DNS doesn't have this problem.

### DNS
```bash
kubectl exec -n svc-demo client -- nslookup my-service                         # same namespace
kubectl exec -n svc-demo client -- nslookup my-service.svc-demo                # <svc>.<ns>
kubectl exec -n svc-demo client -- nslookup my-service.svc-demo.svc.cluster.local
# SRV record for a NAMED port: _<port-name>._<protocol>.<svc>.<ns>
kubectl exec -n svc-demo client -- dig +short SRV _http._tcp.my-multi-port.svc-demo.svc.cluster.local
```
Expected: the A record is the Service's CLUSTER-IP. The SRV answer shows port `80` and the target name.
Pods in **other** namespaces must use at least `my-service.svc-demo`.

## Lab 5 – Service without a selector (manual EndpointSlice)
Point a Service at the nginx pod by IP, the way you would for an external database:
```bash
NGINX_IP=$(kubectl get pod nginx -n svc-demo -o jsonpath='{.status.podIP}')
sed "s/NGINX_POD_IP/$NGINX_IP/" 05-no-selector.yaml | kubectl apply -f -
kubectl get endpointslices -n svc-demo -l kubernetes.io/service-name=manual-service
kubectl exec -n svc-demo client -- curl -s manual-service | head -4
```
Expected: the nginx page. Kubernetes did **not** create a slice; it uses yours. The label `kubernetes.io/service-name` connects the slice to the Service.
Caveat from the docs: `kubectl port-forward svc/manual-service …` fails. The API server won't proxy to endpoints that aren't pods.

## Lab 6 – NodePort
```bash
kubectl apply -f 06-nodeport.yaml
kubectl get svc my-nodeport -n svc-demo                 # PORT(S) 80:30007/TCP
curl -s $(minikube ip):30007/hostname; echo             # from your laptop
# every node answers, even one without a web pod:
kubectl get nodes -o wide
```
Expected: the pod name. `my-nodeport` also has a ClusterIP, so `curl my-nodeport` works inside the cluster.
Experiment: remove `nodePort: 30007`, re-apply, and see a random port picked (normally from the 30086–32767 band).

## Lab 7 – LoadBalancer
```bash
kubectl apply -f 07-loadbalancer.yaml
kubectl get svc my-lb -n svc-demo -w        # EXTERNAL-IP stays <pending> ...
```
minikube has no cloud provider, so in a **second terminal** run:
```bash
minikube tunnel
```
The EXTERNAL-IP is now filled in:
```bash
curl -s http://$(kubectl get svc my-lb -n svc-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')/hostname; echo
kubectl get svc my-lb -n svc-demo -o yaml | grep -A4 '^status'
```
Notice the LB Service also got a nodePort and a clusterIP. Read the commented fields in the file (`allocateLoadBalancerNodePorts`, `loadBalancerClass`, internal-LB annotations).

## Lab 8 – ExternalName
```bash
kubectl apply -f 08-externalname.yaml
kubectl get svc my-database -n svc-demo                 # no CLUSTER-IP, EXTERNAL-IP = example.com
kubectl exec -n svc-demo client -- dig my-database.svc-demo.svc.cluster.local
```
Expected: a **CNAME** `my-database.svc-demo.svc.cluster.local → example.com`, followed by example.com's A records.
Caveat: `curl http://my-database` sends `Host: my-database`, and TLS certificates won't match that name. ExternalName only does DNS, nothing at the HTTP or TLS level.

## Lab 9 – Headless Service
```bash
kubectl apply -f 09-headless.yaml
kubectl get svc my-headless -n svc-demo                 # CLUSTER-IP: None
kubectl exec -n svc-demo client -- dig +short my-headless.svc-demo.svc.cluster.local
kubectl get pods -n svc-demo -l app.kubernetes.io/name=MyApp -o wide
kubectl exec -n svc-demo client -- dig +short my-service.svc-demo.svc.cluster.local   # compare: 1 VIP
```
Expected: the headless name returns **3 A records**, one per pod IP. The normal Service returns a single virtual IP.
There's no kube-proxy load balancing, so the client picks an IP: `curl my-headless:9376/hostname`.
*Without* a selector, a headless Service gets DNS records from EndpointSlices you create yourself (or a CNAME if it is `ExternalName`).

## Lab 10 – Session affinity
```bash
./test.sh http://my-service/hostname 12          # spread across pods
kubectl apply -f 10-session-affinity.yaml
./test.sh http://my-sticky/hostname 12           # always the SAME pod
./test.sh http://my-sticky/hostname 12 client-late   # another client may land on another pod
```
Expected: with `sessionAffinity: ClientIP`, each client IP sticks to one pod for `timeoutSeconds` (default 10800 = 3h).

## Lab 11 – Traffic policies (needs 2+ nodes)
```bash
kubectl apply -f 11-traffic-policy.yaml
kubectl get pods -n svc-demo -o wide            # which node are client and web-* on?
./test.sh http://my-service/hostname 20         # Cluster: pods on all nodes
./test.sh http://my-local-internal/hostname 20  # Local: only pods on client's node
```
Expected: `internalTrafficPolicy: Local` answers only from web pods on the **same node** as `client`. If that node has no web pod, every request fails (`<no answer>`). Traffic is dropped, not sent to another node.

External policy (Local keeps the client source IP and skips nodes without a pod):
```bash
for n in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
  echo -n "$n:30008 -> "; kubectl exec -n svc-demo client -- curl -s -m 2 $n:30008/hostname || echo "no answer"; echo
done
```
Expected: only nodes running a `web` pod answer. A cloud LB health check (`:10256/healthz` from kube-proxy) would mark the other nodes unhealthy.
Optional: when traffic is `Local` and every local endpoint is terminating, kube-proxy still sends traffic to them, so connections drain gracefully (stable v1.28).

## Lab 12 – externalIPs
```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
sed "s/EXTERNAL_IP/$NODE_IP/" 12-external-ips.yaml | kubectl apply -f -   # note the deprecation warning
kubectl get svc my-external-ip -n svc-demo
kubectl exec -n svc-demo client -- curl -s -m 3 $NODE_IP:8080/hostname; echo
```
Expected: `<node-ip>:8080` reaches the Service, because kube-proxy captures traffic to the external IP and port. Kubernetes does not own or route that IP. The cluster admin has to.

## Lab 13 – trafficDistribution (read-only)
```bash
kubectl apply -f 13-traffic-distribution.yaml
kubectl get endpointslices -n svc-demo -l kubernetes.io/service-name=my-prefer-node -o yaml | grep -B2 -A4 hints
```
Read the file comments. `PreferSameNode` and `PreferSameZone` are *preferences* with fallback, unlike `internalTrafficPolicy: Local`, which is a hard rule.

---

## How it works under the hood (virtual IPs)
- The cluster IP is virtual. No interface has it. kube-proxy on every node watches Services and EndpointSlices and writes rules that DNAT `clusterIP:port` to a pod.
- Proxy modes on Linux: `iptables` (current default), `nftables` (recommended going forward, kernel 5.13+), `ipvs` (deprecated). Windows uses `kernelspace`.
- Why not plain round-robin DNS? Clients cache DNS and ignore TTLs, and low TTLs overload DNS.
- See the mode on minikube: `kubectl get cm kube-proxy -n kube-system -o yaml | grep mode`
- See the rules: `minikube ssh -- sudo iptables -t nat -L KUBE-SERVICES -n | grep my-service`
- A specific ClusterIP can be requested with `.spec.clusterIP`. It must be inside `--service-cluster-ip-range`, or the API server returns an error (422).

## Useful commands
```bash
kubectl get svc -n svc-demo -o wide                  # short name: svc
kubectl describe svc <name> -n svc-demo              # Endpoints, TargetPort, NodePort
kubectl get endpointslices -n svc-demo               # backend IPs per Service
kubectl explain service.spec.ports                   # field docs
kubectl expose deploy web -n svc-demo --port=80 --target-port=9376 --name=quick-svc   # imperative
kubectl port-forward svc/my-service -n svc-demo 8080:80   # then curl localhost:8080/hostname
```

## Cleanup
```bash
./cleanup.sh services    # delete all Services (keep the app) to redo the labs
./cleanup.sh all         # delete the svc-demo namespace
# stop 'minikube tunnel' with Ctrl-C if it is running
```

## Version notes from the docs
- EndpointSlices GA v1.21 · `appProtocol` GA v1.20 · Endpoints API deprecated v1.33
- `allocateLoadBalancerNodePorts`, `loadBalancerClass` GA v1.24 · `loadBalancerIP` deprecated v1.24
- Mixed-protocol LoadBalancer GA v1.26 · `internalTrafficPolicy` GA v1.26
- Traffic to terminating endpoints GA v1.28
