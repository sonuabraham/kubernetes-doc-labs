# Use a Service to Access an Application in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/service-access-application-cluster/

> Runs on the default **minikube** cluster (docker driver: the node IP `192.168.58.2` is reachable from the host, no firewall step needed),
> `default` namespace. Files: [hello-application.yaml](hello-application.yaml) (docs, **verbatim**),
> [example-service.yaml](example-service.yaml) (the "service configuration file" alternative the page mentions but doesn't show; **not from the docs**).
>
> **Note:** the sample `describe` output shows `Labels: run=load-balancer-example`. `kubectl expose` copies the **Deployment's** labels,
> and this Deployment has none, so you get `Labels: <none>` (the selector is still right).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `kubectl expose deployment … --type=NodePort` | Service with the Deployment's selector and port; random nodePort 30000-32767 |
| NodePort | every node listens on that port → kube-proxy → one of the endpoints |
| Endpoints | Pod IPs:targetPort of Ready Pods matching the selector |
| Node address | minikube: `minikube ip` or `kubectl cluster-info`; `minikube service <svc> --url` does both |

---

## Lab 1 – Deployment + NodePort (docs)
```bash
cd tasks/access-application-cluster/service-access-application-cluster
kubectl apply -f hello-application.yaml
kubectl get deployments hello-world                  # 2/2
kubectl get replicasets                              # hello-world-5f96c944d   2   2   2
kubectl expose deployment hello-world --type=NodePort --name=example-service
kubectl describe services example-service
#   Labels:                   <none>
#   Selector:                 run=load-balancer-example
#   Type:                     NodePort
#   Port:                     <unset>  8080/TCP
#   NodePort:                 <unset>  31917/TCP
#   Endpoints:                10.244.0.131:8080,10.244.0.130:8080
kubectl get pods --selector="run=load-balancer-example" --output=wide     # the two endpoint IPs, NODE minikube
kubectl cluster-info                                 # Kubernetes control plane is running at https://192.168.58.2:8443
curl http://192.168.58.2:31917
#   Hello, world!
#   Version: 2.0.0
#   Hostname: hello-world-5f96c944d-5cwr8
for i in 1 2 3 4 5 6; do curl -s http://$(minikube ip):31917 | grep Hostname; done     # both Pods answer
minikube service example-service --url               # http://192.168.58.2:31917
```

## Lab 2 – The same Service from a file (not from the docs)
```bash
kubectl delete services example-service
kubectl apply -f example-service.yaml
kubectl get svc example-service                      # NodePort   8080:30080/TCP
curl http://$(minikube ip):30080                     # Hello, world! …
```

## Cleanup
```bash
./cleanup.sh          # = kubectl delete services example-service; kubectl delete deployment hello-world
```
