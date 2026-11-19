# Using kubectl to Create a Deployment – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/kubernetes-basics/deploy-app/deploy-intro/

> Module 2 of [Learn Kubernetes Basics](../../). Runs on the default **minikube**, namespace `default`, commands as in the docs.
>
> **Notes:**
> - The page calls the app "a hello-node application … that uses NGINX to echo back all the requests". `kubernetes-bootcamp:v1` is a
>   **Node.js 6.3.1** server (`server.js`), not NGINX (see module 3).
> - `POD_NAME=$(kubectl get pods -o go-template …)` takes **every** Pod in the namespace. Run the modules in an empty namespace, or add
>   `-l app=kubernetes-bootcamp`.
> - `kubectl proxy` doesn't return. In a script, start it detached (`setsid nohup kubectl proxy >/tmp/proxy.log 2>&1 &`).
> - `kubectl version` warns here: `version difference between client (1.35) and server (1.37) exceeds the supported minor version skew of +/-1`.

## Key ideas (read first)

| Term | Meaning |
|---|---|
| Deployment | desired state for your app; its controller keeps the Pods running and replaces them if a node dies |
| `kubectl action resource` | `create`, `get`, `describe`, `delete` … on `deployment`, `pods`, `nodes` … |
| `kubectl proxy` | localhost:8001 → API server with your credentials; also reaches Pods through the API server's proxy |

## Lab
```bash
kubectl version              # Client v1.35.10, Server v1.37.0 (+ skew warning)
kubectl get nodes            # minikube   Ready   control-plane
kubectl create deployment kubernetes-bootcamp --image=gcr.io/google-samples/kubernetes-bootcamp:v1
kubectl get deployments
#   kubernetes-bootcamp   1/1   1   1   1s
kubectl proxy                # second terminal: Starting to serve on 127.0.0.1:8001
curl http://localhost:8001/version
#   { "major": "1", "minor": "37", … "gitVersion": "v1.37.0", … "platform": "linux/amd64" }
export POD_NAME=$(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
echo Name of the Pod: $POD_NAME
#   Name of the Pod: kubernetes-bootcamp-5cc66bcc9b-rnd2h
curl http://localhost:8001/api/v1/namespaces/default/pods/$POD_NAME:8080/proxy/
#   Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-rnd2h | v=1
```
The image is AMD64-only (page note). The minikube node here is `amd64`, so it runs natively.

Keep the Deployment and the proxy for the next module: [explore-intro](../../explore/explore-intro/).
