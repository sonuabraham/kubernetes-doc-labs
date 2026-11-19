# Using a Service to Expose Your App – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/kubernetes-basics/expose/expose-intro/

> Module 4 of [Learn Kubernetes Basics](../../). Continues with the `kubernetes-bootcamp` Deployment. Commands as in the docs.
>
> **Notes:**
> - The `curl` straight after `kubectl expose` failed once (`Could not connect to server`); kube-proxy needed **< 1 s** (measured 0.85 s) to
>   program the new NodePort. Retry if it happens.
> - The page's `minikube service … --url` sample (`http://127.0.0.1:51082`, "Docker driver on darwin") is macOS-specific. On Linux it prints
>   `http://<minikube ip>:<nodePort>` and needs no open terminal.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Service | stable virtual IP + DNS name in front of the Pods its **selector** matches |
| `type: NodePort` | also opens a port (30000-32767) on every node |
| Labels | key/value pairs on objects; selectors (`-l`) filter on them; a Service finds Pods by label |
| Deleting the Service | the app keeps running, it's just unreachable from outside |

## Lab
```bash
kubectl get pods
kubectl get services                              # only "kubernetes"
kubectl expose deployment/kubernetes-bootcamp --type="NodePort" --port 8080
kubectl describe services/kubernetes-bootcamp
#   Selector:  app=kubernetes-bootcamp   Type: NodePort   Port: 8080/TCP   NodePort: 31273/TCP   Endpoints: 10.244.0.18:8080
export NODE_PORT="$(kubectl get services/kubernetes-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}')"
echo "NODE_PORT=$NODE_PORT"                       # NODE_PORT=31273
curl http://"$(minikube ip):$NODE_PORT"
#   Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-rnd2h | v=1     (retry once if "Could not connect")
minikube service kubernetes-bootcamp --url        # http://192.168.58.2:31273
kubectl describe deployment                       # Labels: app=kubernetes-bootcamp   Selector: app=kubernetes-bootcamp
kubectl get pods -l app=kubernetes-bootcamp
kubectl get services -l app=kubernetes-bootcamp
export POD_NAME="$(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')"
kubectl label pods "$POD_NAME" version=v1
kubectl describe pods "$POD_NAME"                 # Labels: app=kubernetes-bootcamp, pod-template-hash=5cc66bcc9b, version=v1
kubectl get pods -l version=v1
kubectl delete service -l app=kubernetes-bootcamp
kubectl get services                              # only "kubernetes" again
curl http://"$(minikube ip):$NODE_PORT"           # curl: (7) … Could not connect to server
kubectl exec -ti $POD_NAME -- curl http://localhost:8080
#   Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-rnd2h | v=1   <- the app is still running
```
Next: [scale-intro](../../scale/scale-intro/).
