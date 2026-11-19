# Running Multiple Instances of Your App – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/kubernetes-basics/scale/scale-intro/

> Module 5 of [Learn Kubernetes Basics](../../). Continues with the `kubernetes-bootcamp` Deployment (its Service was deleted at the end of
> module 4, so the page's first command recreates one, now as `LoadBalancer`). Commands as in the docs.
> **Note:** on minikube the `LoadBalancer` gets no external IP (`<pending>`); the docs use its NodePort, which every LoadBalancer Service has.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `kubectl scale --replicas=N` | changes the Deployment's desired count; the ReplicaSet creates/deletes Pods |
| Service endpoints | follow the Ready Pods automatically; traffic is spread over them |
| Scale down | the newest Pods are removed first |

## Lab
```bash
kubectl expose deployment/kubernetes-bootcamp --type="LoadBalancer" --port 8080
kubectl get deployments            # kubernetes-bootcamp   1/1   1   1
kubectl get rs                     # kubernetes-bootcamp-5cc66bcc9b   1   1   1
kubectl scale deployments/kubernetes-bootcamp --replicas=4
kubectl get deployments            # 4/4   4   4
kubectl get pods -o wide           # four Pods, IPs 10.244.0.18–.21, all on minikube
kubectl describe deployments/kubernetes-bootcamp
#   Replicas: 4 desired | 4 updated | 4 total | 4 available | 0 unavailable
#   Scaled up replica set kubernetes-bootcamp-5cc66bcc9b from 1 to 4
kubectl describe services/kubernetes-bootcamp
#   Type: LoadBalancer   Endpoints: 10.244.0.18:8080,10.244.0.19:8080,10.244.0.20:8080 + 1 more...
export NODE_PORT="$(kubectl get services/kubernetes-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}')"
for i in $(seq 8); do curl -s http://"$(minikube ip):$NODE_PORT"; done | sort | uniq -c
#   3 … Running on: kubernetes-bootcamp-5cc66bcc9b-7wff4 | v=1
#   1 … Running on: kubernetes-bootcamp-5cc66bcc9b-hvsb8 | v=1
#   3 … Running on: kubernetes-bootcamp-5cc66bcc9b-rmpbp | v=1
#   1 … Running on: kubernetes-bootcamp-5cc66bcc9b-rnd2h | v=1     <- all four answer
kubectl scale deployments/kubernetes-bootcamp --replicas=2
kubectl get pods -o wide           # two Running, two Terminating (newest ones go first)
```
Next: [update-intro](../../update/update-intro/).
