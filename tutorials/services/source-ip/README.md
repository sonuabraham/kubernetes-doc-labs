# Using Source IP – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/services/source-ip/

> Runs on the default **minikube**: **one** node, kube-proxy in **iptables** mode. All commands are the docs' commands, apart from the
> places marked NOT from the docs. Single node means the "other nodes drop the packet / fail the health check" parts can't happen here,
> but every source-IP effect can be seen.
>
> **Setup for the LoadBalancer part (NOT from the docs):**
> - `EXTERNAL-IP` comes from the fake cloud LB controller of
>   [tasks/…/create-external-load-balancer](../../../tasks/access-application-cluster/create-external-load-balancer/) (`203.0.113.200`).
> - A real **outside client** is a throwaway `alpine:3` container on the `minikube` Docker network (`192.168.58.3`). It routes
>   203.0.113.0/24 via the node. The route lives only in that container's own network namespace (`--cap-add NET_ADMIN`).
>
> **Found:**
> - The health check on `healthCheckNodePort` answers **JSON**, not the page's `1 Service Endpoints found` / `No Service Endpoints Found`:
>   `{"service":{"namespace":"default","name":"loadbalancer"},"localEndpoints":1,"serviceProxyHealthy":true}` → HTTP 200.
>   With no local endpoint: `"localEndpoints": 0` → **HTTP 503**. Cloud LBs look at the status code.
> - "SNAT'd" here doesn't mean "the node IP". On minikube the Pod sees **10.244.0.1** (the node's address on the Pod bridge), not
>   192.168.58.2.

## Key ideas (read first)

| Service type | Client IP the Pod sees |
|---|---|
| ClusterIP, from a Pod (iptables mode) | the **client Pod's IP** (no SNAT) |
| NodePort, default (`externalTrafficPolicy: Cluster`) | a **node** address (SNAT): the packet may be forwarded to another node |
| NodePort, `externalTrafficPolicy: Local` | the **real client IP**; nodes without a local endpoint drop the traffic |
| LoadBalancer, default | SNAT like NodePort |
| LoadBalancer, `Local` | real client IP; `healthCheckNodePort` lets the cloud LB skip nodes without endpoints (HTTP 503) |

## Lab 1 – ClusterIP
```bash
kubectl create deployment source-ip-app --image=registry.k8s.io/echoserver:1.10
kubectl get nodes                                   # minikube   Ready   control-plane   v1.37.0
minikube ssh -- curl -s http://localhost:10249/proxyMode      # iptables
kubectl expose deployment source-ip-app --name=clusterip --port=80 --target-port=8080
kubectl get svc clusterip                           # clusterip   ClusterIP   10.111.180.205   80/TCP
kubectl run busybox -it --image=busybox:1.28 --restart=Never --rm
  ip addr                                           # eth0 … inet 10.244.0.31/24
  wget -qO - 10.111.180.205                         # client_address=10.244.0.31    <- the client Pod itself
```

## Lab 2 – NodePort
```bash
kubectl expose deployment source-ip-app --name=nodeport --port=80 --target-port=8080 --type=NodePort
NODEPORT=$(kubectl get -o jsonpath="{.spec.ports[0].nodePort}" services nodeport)
NODES=$(kubectl get nodes -o jsonpath='{ $.items[*].status.addresses[?(@.type=="InternalIP")].address }')
for node in $NODES; do curl -s $node:$NODEPORT | grep -i client_address; done
#   client_address=10.244.0.1            <- SNAT (the host is really 192.168.58.1 on the minikube bridge)
kubectl patch svc nodeport -p '{"spec":{"externalTrafficPolicy":"Local"}}'
for node in $NODES; do curl --connect-timeout 1 -s $node:$NODEPORT | grep -i client_address; done
#   client_address=192.168.58.1          <- the real client (this host)
```

## Lab 3 – LoadBalancer
```bash
../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh start      # NOT from the docs
kubectl expose deployment source-ip-app --name=loadbalancer --port=80 --target-port=8080 --type=LoadBalancer
kubectl get svc loadbalancer                        # loadbalancer   LoadBalancer   10.105.116.43   203.0.113.200   80:31263/TCP
# docs: curl 203.0.113.140 – here from the outside-client container (NOT from the docs):
docker run --rm --network minikube --cap-add NET_ADMIN alpine:3 \
  sh -c "ip route add 203.0.113.0/24 via $(minikube ip); wget -qO- http://203.0.113.200 | grep client_address"
#   client_address=10.244.0.1            <- SNAT
kubectl patch svc loadbalancer -p '{"spec":{"externalTrafficPolicy":"Local"}}'
kubectl get svc loadbalancer -o yaml | grep -i healthCheckNodePort      # healthCheckNodePort: 31342
kubectl get pod -o wide -l app=source-ip-app        # source-ip-app-9b695756c-ww46w   10.244.0.30   minikube
minikube ssh -- curl localhost:31342/healthz
#   {"service":{"namespace":"default","name":"loadbalancer"},"localEndpoints":1,"serviceProxyHealthy":true}
# (same docker run as above)
#   client_address=192.168.58.3          <- the outside client's real IP
```
NOT from the docs – a node without endpoints, simulated by scaling to 0:
```bash
kubectl scale deploy source-ip-app --replicas=0
minikube ssh -- "curl -s -w '\nHTTP %{http_code}\n' localhost:31342/healthz"      # "localEndpoints": 0 … HTTP 503
kubectl scale deploy source-ip-app --replicas=1                                     # → HTTP 200 again
```

## Cleanup
```bash
./cleanup.sh       # docs: kubectl delete svc -l app=source-ip-app; kubectl delete deployment source-ip-app  (+ busybox, fake LB)
```
