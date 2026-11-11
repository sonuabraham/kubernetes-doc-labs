# Service Internal Traffic Policy – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/service-traffic-policy/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **internalTrafficPolicy** | Stable since 1.26. For traffic **from inside** the cluster to a Service: `Cluster` (default, any endpoint) or `Local` (**only endpoints on the same node** as the client). |
| **Local, no local endpoint** | Traffic is **dropped**. kube-proxy doesn't fall back to other nodes. |
| **Use cases** | Node-local agents (a DaemonSet logging/metrics endpoint): keep traffic on the node, no extra hop. |
| **How** | kube-proxy builds a per-node endpoint list from EndpointSlices (`nodeName`). In iptables mode a `KUBE-SVL-…` (local) chain replaces `KUBE-SVC-…`. |
| **Related** | `externalTrafficPolicy` (for NodePort/LoadBalancer, see `../service`) and `trafficDistribution`. |

## The demo app
[my-service-local.yaml](my-service-local.yaml) is the docs manifest **verbatim**: `my-service`, selector `app.kubernetes.io/name: MyApp`, port 80 → 9376, `internalTrafficPolicy: Local`.

---

## Lab 1 – A Local Service and its kube-proxy rules
```bash
cd concepts/services-networking/service-traffic-policy
kubectl create namespace itp-demo
kubectl create deploy myapp -n itp-demo --image=registry.k8s.io/e2e-test-images/agnhost:2.53 --replicas=2 -- /agnhost netexec --http-port=9376
kubectl patch deploy myapp -n itp-demo -p '{"spec":{"template":{"metadata":{"labels":{"app.kubernetes.io/name":"MyApp"}}}}}'
kubectl apply -f my-service-local.yaml -n itp-demo ; kubectl rollout status deploy/myapp -n itp-demo
minikube ssh -- "sudo iptables -t nat -S | grep 'itp-demo/my-service'"
#   -A KUBE-SERVICES -d 10.111.87.116/32 ... -j KUBE-SVL-NJ7KYBO2FA7W     <- "SVL" = service, LOCAL endpoints only
#   -A KUBE-SVL-… -> 10.244.0.180:9376 (probability 0.5) / -> 10.244.0.181:9376
```
Compare with a normal Service (`kubectl get svc -n ../` any default one): `KUBE-SVC-…` chains.

## Lab 2 – Traffic stays on the node
```bash
kubectl run c -n itp-demo --restart=Never --image=busybox:1.36 -- sh -c 'for i in 1 2 3 4; do wget -qO- my-service/hostname; echo; done'
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/c -n itp-demo ; kubectl logs c -n itp-demo | sort | uniq -c
#   3 myapp-…-9g78n   1 myapp-…-plz8m     <- both endpoints are on the client's node (single-node cluster)
```

## Lab 3 – No local endpoint → dropped (needs 2 nodes)
On the 2-node `arch-lab` profile (`../../architecture`), pin `myapp` to `arch-lab-m02` (`nodeSelector`) and run the client on `arch-lab`:
```bash
kubectl run c2 -n itp-demo --restart=Never --image=busybox:1.36 --overrides='{"spec":{"nodeName":"arch-lab"}}' -- wget -T 3 -qO- my-service/hostname
kubectl logs c2 -n itp-demo          # wget: download timed out   <- no endpoint on arch-lab, and no cross-node fallback
```
Switch to `internalTrafficPolicy: Cluster` and the same request succeeds through the other node.

---

## Useful commands
```bash
kubectl get svc -o custom-columns=NAME:.metadata.name,ITP:.spec.internalTrafficPolicy,ETP:.spec.externalTrafficPolicy
kubectl get endpointslices -l kubernetes.io/service-name=<svc> -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} {.nodeName}{"\n"}{end}'
```

## Cleanup
```bash
./cleanup.sh
```
