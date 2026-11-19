# Viewing Pods and Nodes – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/kubernetes-basics/explore/explore-intro/

> Module 3 of [Learn Kubernetes Basics](../../). Continues with the `kubernetes-bootcamp` Deployment and `kubectl proxy` from module 2.
> All commands as in the docs. The `-ti … bash` step is shown non-interactively here; the commands are the same.

## Key ideas (read first)

| Command | Shows |
|---|---|
| `kubectl get pods` / `describe pods` | Pod list / details: node, IP, image, state, events |
| `kubectl logs` | the container's stdout |
| `kubectl exec` | run a command in the container (`env`, a shell) |

## Lab
```bash
kubectl get pods             # kubernetes-bootcamp-5cc66bcc9b-rnd2h   1/1   Running
kubectl describe pods
#   Node:   minikube/192.168.58.2
#   IP:     10.244.0.18
#   Image:  gcr.io/google-samples/kubernetes-bootcamp:v1
#   Port:   <none>              <- kubectl create deployment doesn't declare the port; the app listens on 8080 anyway
#   State:  Running
export POD_NAME="$(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')"
curl http://localhost:8001/api/v1/namespaces/default/pods/$POD_NAME:8080/proxy/
#   Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-rnd2h | v=1
kubectl logs "$POD_NAME"
#   Kubernetes Bootcamp App Started At: 2026-11-19T08:31:39.550Z | Running On:  kubernetes-bootcamp-5cc66bcc9b-rnd2h
#   Running On: kubernetes-bootcamp-5cc66bcc9b-rnd2h | Total Requests: 1 | App Uptime: 0.572 seconds | …
kubectl exec "$POD_NAME" -- env
#   HOSTNAME=kubernetes-bootcamp-5cc66bcc9b-rnd2h   NODE_VERSION=6.3.1   NPM_CONFIG_LOGLEVEL=info   KUBERNETES_SERVICE_HOST=…
kubectl exec -ti $POD_NAME -- bash
  cat server.js              # var http = require('http'); … response.write("Hello Kubernetes bootcamp! | Running on: ") …
  curl http://localhost:8080 # Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-rnd2h | v=1
  exit
```
Next: [expose-intro](../../expose/expose-intro/).
