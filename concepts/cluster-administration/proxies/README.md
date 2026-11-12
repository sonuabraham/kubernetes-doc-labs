# Proxies in Kubernetes – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/cluster-administration/proxies/

> No YAML on the page. [00-app.yaml](00-app.yaml) is an agnhost HTTP app (2 replicas, `/hostname`) behind a ClusterIP Service `web` and a LoadBalancer Service `web-lb`. The lab goes through the page's five proxies.

## Key ideas (read first)

| # | Proxy | Where | Protocol | Purpose |
|---|---|---|---|---|
| 1 | **kubectl proxy** | your machine | client HTTP → API HTTPS, adds your credentials | Easy local access to the REST API |
| 2 | **API server proxy** | inside kube-apiserver | HTTPS | Reach Pods, Services (load-balanced) and nodes (kubelet) from outside the cluster network: `/api/v1/namespaces/<ns>/services/<svc>:<port>/proxy/…` |
| 3 | **kube-proxy** | every node | TCP/UDP/SCTP, not HTTP-aware | Implements Service virtual IPs (iptables/IPVS/nftables) |
| 4 | **LB in front of API servers** | infra (nginx, HAProxy, cloud LB) | | HA for several API servers |
| 5 | **Cloud load balancers** | cloud provider | usually TCP/UDP | `type: LoadBalancer` Services |
| | **Redirects** | | | Deprecated, replaced by proxies |

---

## Lab
```bash
cd concepts/cluster-administration/proxies
kubectl apply -f 00-app.yaml
kubectl proxy --port=8001 &                                    # 1: localhost HTTP, no token needed by the client
curl -s http://127.0.0.1:8001/api/v1/namespaces/proxies-lab/services | jq -r '.items[].metadata.name'       # web web-lb
```
**2 – the API server proxy:**
```bash
for i in $(seq 1 20); do curl -s http://127.0.0.1:8001/api/v1/namespaces/proxies-lab/services/web:http/proxy/hostname; echo; done | sort | uniq -c
#   12 web-…-7fswv     8 web-…-jkl6t          <- load-balanced across endpoints (a first run of 4 requests all hit one Pod: it's random, not round-robin)
P=$(kubectl get pod -n proxies-lab -l app=web -o jsonpath='{.items[0].metadata.name}')
curl -s http://127.0.0.1:8001/api/v1/namespaces/proxies-lab/pods/$P:8080/proxy/hostname      # one specific Pod
curl -s http://127.0.0.1:8001/api/v1/nodes/minikube/proxy/healthz                             # ok   - the kubelet
```
**3 – kube-proxy:**
```bash
IP=$(kubectl get svc web -n proxies-lab -o jsonpath='{.spec.clusterIP}')
minikube ssh -- "sudo iptables -t nat -S KUBE-SERVICES | grep $IP"
#   -A KUBE-SERVICES -d 10.106.101.118/32 -p tcp -m comment --comment "proxies-lab/web:http cluster IP" -m tcp --dport 80 -j KUBE-SVC-BEU7KWX7RHJWC3XV
minikube ssh -- "sudo iptables -t nat -S | grep -c 'proxies-lab/web:http'"        # 8 rules for one Service with 2 endpoints
```
**4/5 – infrastructure:**
```bash
kubectl get svc web-lb -n proxies-lab        # EXTERNAL-IP <pending>   <- no cloud provider; `minikube tunnel` plays that role
```
minikube has a single API server, so there's no proxy #4.

---

## Useful commands
```bash
kubectl proxy --port=8001 ; kubectl port-forward svc/<s> 8080:80
kubectl get --raw /api/v1/namespaces/<ns>/services/<svc>:<port>/proxy/<path>
```

## Cleanup
```bash
./cleanup.sh       # and stop kubectl proxy (kill %1)
```
