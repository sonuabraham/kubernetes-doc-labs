# Exposing an External IP Address to Access an Application in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/stateless-application/expose-external-ip-address/

> The page wants a cloud cluster (GKE/AWS). This lab runs on the default **minikube**, namespace `default`.
> [load-balancer-example.yaml](load-balancer-example.yaml) is the docs example **verbatim**.
>
> **On minikube:**
> - With no cloud, `EXTERNAL-IP` stays `<pending>` forever. The page's "wait for a minute" doesn't help. The `LoadBalancer` Service still
>   works as a NodePort: `curl http://$(minikube ip):<nodePort>` and `minikube service my-service --url` (the page mentions the latter) work at once.
> - To see the cloud part, this lab (NOT from the docs) reuses the fake cloud LB controller from
>   [tasks/…/create-external-load-balancer](../../../tasks/access-application-cluster/create-external-load-balancer/) (fakecloud CCM, `service`
>   controller only). It hands out `203.0.113.200` (TEST-NET-3) as `LoadBalancer Ingress`. That address isn't routable from the host
>   (`curl` times out), but kube-proxy programs it **inside the node**, so `minikube ssh -- curl http://203.0.113.200:8080` answers.
>   (`minikube tunnel` would be the minikube way, but it needs sudo for routes.)
> - The fake controller logs `Warning UnAvailableLoadBalancer … There are no available nodes for LoadBalancer`. The only node is a control
>   plane with `node.kubernetes.io/exclude-from-external-load-balancers`, as a real cloud would see it too.
> - `Hostname:` in the reply is the Pod name, not a container ID like the page's `0bd46b45f32f`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `kubectl expose … --type=LoadBalancer` | ClusterIP + NodePort + asks the **cloud controller** for an external LB |
| `LoadBalancer Ingress` | the address the cloud gave; written to `.status.loadBalancer.ingress` by the controller, not by Kubernetes core |
| `<pending>` | no controller has answered (no cloud, or it failed) |
| Endpoints | the 5 Pod IPs:8080 behind the Service |

## Lab
```bash
kubectl apply -f load-balancer-example.yaml
kubectl get deployments hello-world                 # hello-world   5/5   5   5
kubectl describe deployments hello-world            # Replicas: 5 desired | 5 updated | 5 total | 5 available   NewReplicaSet: hello-world-c4d7697c9
kubectl get replicasets                             # hello-world-c4d7697c9   5   5   5
kubectl describe replicasets                        # Controlled By: Deployment/hello-world   Pods Status: 5 Running
kubectl expose deployment hello-world --type=LoadBalancer --name=my-service
kubectl get services my-service
#   my-service   LoadBalancer   10.103.194.101   <pending>   8080:32679/TCP   11s      <- stays pending on minikube

# minikube access (works without an external IP)
curl http://$(minikube ip):32679                    # Hello, world! / Version: 2.0.0 / Hostname: hello-world-c4d7697c9-d6m9g
minikube service my-service --url                   # http://192.168.58.2:32679

# NOT from the docs – a (fake) cloud load balancer
../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh start
kubectl get services my-service
#   my-service   LoadBalancer   10.103.194.101   203.0.113.200   8080:32679/TCP   20s
kubectl describe services my-service
#   LoadBalancer Ingress:     203.0.113.200 (VIP)
#   Port:                     <unset>  8080/TCP
#   NodePort:                 <unset>  32679/TCP
#   Endpoints:                10.244.0.28:8080,10.244.0.24:8080,10.244.0.27:8080 + 2 more...
#   Events: EnsuringLoadBalancer / UnAvailableLoadBalancer (no available nodes) / EnsuredLoadBalancer
kubectl get pods --output=wide                      # 5 Pods 10.244.0.24–.28, all on minikube
curl http://203.0.113.200:8080                      # times out from the host (TEST-NET)
minikube ssh -- curl -s http://203.0.113.200:8080   # Hello, world! / Version: 2.0.0 / Hostname: hello-world-c4d7697c9-d6m9g
```

## Cleanup
```bash
./cleanup.sh     # docs: kubectl delete services my-service; kubectl delete deployment hello-world  (+ stops the fake LB after the Service is gone)
```
