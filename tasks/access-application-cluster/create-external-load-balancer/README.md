# Create an External Load Balancer – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs' inline examples, **verbatim**):
> [example-service.yaml](example-service.yaml), [example-service-local.yaml](example-service-local.yaml) (`externalTrafficPolicy: Local`).
> Not from the docs: [example-deployment.yaml](example-deployment.yaml) (the `example` app the page assumes; agnhost `/clientip` on 9376)
> and [run-fake-lb.sh](run-fake-lb.sh).
>
> **No cloud here.** minikube has no load balancer controller, so `EXTERNAL-IP` stays `<pending>` (`minikube tunnel` needs sudo, see
> [connecting-frontend-backend](../connecting-frontend-backend/)). `run-fake-lb.sh` runs only the **service controller** of the fakecloud
> cloud-controller-manager built in [developing-cloud-controller-manager](../../administer-cluster/developing-cloud-controller-manager/).
> It is real CCM code, so you see the real fields, events, and finalizer. The IPs (`203.0.113.x`, TEST-NET) aren't routable from your machine,
> but kube-proxy serves them inside the node.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `type: LoadBalancer` | ClusterIP + NodePort + an external LB set up by the cloud's service controller; IP lands in `status.loadBalancer.ingress` |
| `externalTrafficPolicy: Cluster` | any node forwards (maybe to another node), source IP is **SNATed** |
| `externalTrafficPolicy: Local` | only nodes with a local endpoint answer; **client IP kept**; `healthCheckNodePort` tells the LB which nodes |
| Finalizer `service.kubernetes.io/load-balancer-cleanup` | the Service can't disappear before the cloud LB is deleted |

---

## Step 0 – App and fake LB controller
```bash
cd tasks/access-application-cluster/create-external-load-balancer
kubectl apply -f example-deployment.yaml
ls ../../administer-cluster/developing-cloud-controller-manager/fakecloud-ccm/bin/fakecloud-ccm   # build it first if missing (see that lab)
```

## Lab 1 – Without a cloud (docs, minikube reality)
```bash
kubectl apply -f example-service.yaml
kubectl get svc example-service
#   example-service   LoadBalancer   10.109.142.82   <pending>   8765:31009/TCP
kubectl get svc example-service -o jsonpath='{.metadata.finalizers}'       # (empty: nobody manages LBs)
minikube service example-service --url          # http://192.168.58.2:31009   <- the docs' minikube note: you get the NodePort
```

## Lab 2 – With a (fake) cloud LB (docs)
```bash
./run-fake-lb.sh start
kubectl get svc example-service
#   example-service   LoadBalancer   10.109.142.82   203.0.113.200   8765:31009/TCP
kubectl describe services example-service | grep -E 'LoadBalancer Ingress|NodePort:|Endpoints'
#   LoadBalancer Ingress:     203.0.113.200 (VIP)
#   NodePort:                 <unset>  31009/TCP
#   Endpoints:                10.244.0.140:9376,10.244.0.139:9376
kubectl get events --field-selector involvedObject.name=example-service -o custom-columns=REASON:.reason,MSG:.message
#   EnsuringLoadBalancer      Ensuring load balancer
#   UnAvailableLoadBalancer   There are no available nodes for LoadBalancer     <- minikube's control-plane node is excluded from LBs
#   EnsuredLoadBalancer       Ensured load balancer
kubectl get svc example-service -o jsonpath='{.metadata.finalizers}'
#   ["service.kubernetes.io/load-balancer-cleanup"]
```

## Lab 3 – Preserving the client source IP (docs)
```bash
curl http://$(minikube ip):31009/clientip                          # 10.244.0.1:31888     <- Cluster: SNAT to the node's bridge IP
minikube ssh -- curl -s http://203.0.113.200:8765/clientip         # 10.244.0.1:…        (the LB IP works inside the node)
kubectl apply -f example-service-local.yaml
kubectl get svc example-service -o jsonpath='{.spec.externalTrafficPolicy} {.spec.healthCheckNodePort}'    # Local 32199
curl http://$(minikube ip):31009/clientip                          # 192.168.58.1:38606   <- your machine's real address
curl http://$(minikube ip):32199/
#   { "service": {…"name": "example-service"}, "localEndpoints": 2, "serviceProxyHealthy": true }
kubectl scale deploy example --replicas=0
curl -s -w ' HTTP %{http_code}\n' http://$(minikube ip):32199/       # "localEndpoints": 0 … HTTP 503   <- the LB drops this node
kubectl scale deploy example --replicas=2
```

## Lab 4 – Garbage collecting load balancers (docs)
```bash
./run-fake-lb.sh stop                          # "the cloud controller is down"
kubectl delete svc example-service --wait=false
kubectl get svc example-service -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}'
#   2026-11-17T11:38:01Z ["service.kubernetes.io/load-balancer-cleanup"]     <- still there
./run-fake-lb.sh start
kubectl wait --for=delete svc/example-service  # condition met   (log: reason="DeletedLoadBalancer")
```

## Lab 5 – `kubectl expose` (docs)
```bash
kubectl expose deployment example --port=8765 --target-port=9376 --name=example-service --type=LoadBalancer
kubectl get svc example-service                # … 203.0.113.200   8765:31590/TCP
kubectl describe svc example-service | grep -E '^Labels|^Selector'    # app=example (copied from the Deployment)
```

## Cleanup
```bash
./cleanup.sh          # deletes the Service while the fake controller still runs, then stops it
```
