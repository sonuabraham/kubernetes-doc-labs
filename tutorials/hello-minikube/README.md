# Hello Minikube – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/hello-minikube/

> Runs on the default **minikube** cluster (minikube v1.39.0, Kubernetes v1.37.0) with the docs' commands as written. Two deliberate differences:
> - The docs' last step stops/deletes minikube. Every lab in this repo uses that cluster, so [cleanup.sh](cleanup.sh) only deletes the app
>   (and disables the dashboard addon again, which was off before).
> - `metrics-server` is already enabled here (other labs need it), so the "enable/disable metrics-server" steps are only described.
>
> **Notes:**
> - The `kubectl get pod,svc -n kube-system` sample output is very old (`kube-addon-manager`, `influxdb-grafana`, `monitoring-grafana`). Today the
>   metrics-server addon adds only `metrics-server` (Pod + Service on **443**, not 80).
> - `kubectl top pods` right after deploying: `error: metrics not available yet` (another message than the docs' `Metrics API not available`);
>   the first values came about a minute later.
> - `minikube service hello-node` opens a browser; `--url` just prints the URL, which suits a terminal.

## Key ideas (read first)

| Command | What it does |
|---|---|
| `minikube start` / `status` | single-node cluster (control plane + worker on one node) |
| `kubectl create deployment … -- /agnhost netexec --http-port=8080` | Deployment → ReplicaSet → Pod running the agnhost test web server |
| `kubectl expose … --type=LoadBalancer` | Service; on minikube the external IP stays `<pending>`, use the NodePort via `minikube service` |
| `minikube addons` | optional cluster components (dashboard, metrics-server, ingress …) |

---

## Lab
```bash
cd tutorials/hello-minikube
minikube status
#   host: Running   kubelet: Running   apiserver: Running   kubeconfig: Configured
minikube dashboard --url        # leave running in another terminal
#   http://127.0.0.1:46301/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/    (HTTP 200)
kubectl create deployment hello-node --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
kubectl get deployments                         # hello-node   1/1   1   1
kubectl get pods                                # hello-node-6f8b554fb7-525nh   1/1   Running
kubectl get events                              # Scheduled → Pulled → Created → Started
kubectl config view
kubectl logs hello-node-6f8b554fb7-525nh
#   I1119 08:29:09.301388  1 log.go:245] Started HTTP server on port 8080
#   I1119 08:29:09.301635  1 log.go:245] Started UDP server on port  8081
kubectl expose deployment hello-node --type=LoadBalancer --port=8080
kubectl get services
#   hello-node   LoadBalancer   10.109.20.146   <pending>   8080:31253/TCP
minikube service hello-node --url               # http://192.168.58.2:31253
curl http://192.168.58.2:31253/hostname         # hello-node-6f8b554fb7-525nh
curl "http://192.168.58.2:31253/echo?msg=hello" # hello
minikube addons list                            # dashboard, metrics-server, storage-provisioner, default-storageclass … enabled
kubectl get pod,svc -n kube-system              # … pod/metrics-server-…  service/metrics-server  ClusterIP  …  443/TCP
kubectl top pods
#   hello-node-6f8b554fb7-525nh   2m   40Mi     (first ~minute: error: metrics not available yet)
```
On a cluster where metrics-server is off: `minikube addons enable metrics-server` … `minikube addons disable metrics-server`.

## Cleanup
```bash
./cleanup.sh       # kubectl delete service/deployment hello-node + dashboard addon off   (no minikube stop/delete, see above)
```
