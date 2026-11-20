# Connecting Applications with Services – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/services/connect-applications-service/

> Runs on the default **minikube**, namespace `default`. Files, **verbatim** from the docs:
> - [run-my-nginx.yaml](run-my-nginx.yaml), [nginx-svc.yaml](nginx-svc.yaml) (the declarative form of `kubectl expose`),
>   [nginx-secure-app.yaml](nginx-secure-app.yaml), [curlpod.yaml](curlpod.yaml)
> - [default.conf](default.conf): the nginx config exactly as the page prints it in `kubectl describe configmap nginxconfigmap`
> - [nginxsecrets.template.yaml](nginxsecrets.template.yaml): the page's Secret template (fill in your own base64 cert/key; a generated
>   key is never committed here)
>
> **Found:**
> - **"Securing the Service" doesn't run as written on current runtimes.** Both images are Docker **schema 1**:
>   `bprashanth/nginxhttps:1.0` and `radial/busyboxplus:curl` fail with
>   `not implemented: media type "application/vnd.docker.distribution.manifest.v1+prettyjws"` (containerd 2.x).
>   [convert-images.sh](convert-images.sh) (NOT from the docs) converts them with skopeo and loads them into minikube under the same
>   names. After that the manifests work unchanged.
> - `make keys …` needs a Makefile and Go from an archived repo (`kubernetes/examples/_archived/https-nginx`), and `default.conf` isn't
>   provided either. This lab uses the page's manual `openssl` path and takes `default.conf` from the page's own output.
> - `radial/busyboxplus:curl` contains **curl 7.35.0 / OpenSSL 1.0.1f** (2014).
> - minikube nodes have no `ExternalIP` (`kubectl get nodes -o yaml | grep ExternalIP` prints nothing). Use the InternalIP
>   (`minikube ip`). `type: LoadBalancer` stays `<pending>` without a cloud; here the fake LB controller from
>   [tasks/…/create-external-load-balancer](../../../tasks/access-application-cluster/create-external-load-balancer/) supplies `203.0.113.200`
>   (reachable inside the node only).
> - The page has no cleanup section; see [cleanup.sh](cleanup.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Pod IPs | every Pod gets its own IP; Pods come and go, so the IPs change |
| Service | stable ClusterIP + DNS name in front of the Pods its selector matches; EndpointSlices list the current Pod IPs |
| Env vars `MY_NGINX_SERVICE_HOST/PORT` | injected only into Pods started **after** the Service exists |
| DNS | `my-nginx` → ClusterIP (CoreDNS `kube-dns` at 10.96.0.10) |
| TLS | cert + key in a `kubernetes.io/tls` Secret, nginx config in a ConfigMap, both mounted into the Pod |
| NodePort / LoadBalancer | expose outside the cluster |

## Lab 1 – Pods and a Service
```bash
kubectl apply -f ./run-my-nginx.yaml
kubectl get pods -l run=my-nginx -o wide             # 2 Pods, 10.244.0.23 / .24 on minikube
kubectl get pods -l run=my-nginx -o custom-columns=POD_IP:.status.podIPs
#   [map[ip:10.244.0.23]]   [map[ip:10.244.0.24]]
kubectl expose deployment/my-nginx                    # = nginx-svc.yaml
kubectl get svc my-nginx                              # my-nginx   ClusterIP   10.98.155.117   80/TCP
kubectl describe svc my-nginx                         # Selector run=my-nginx … Endpoints: 10.244.0.23:80,10.244.0.24:80
kubectl get endpointslices -l kubernetes.io/service-name=my-nginx
#   my-nginx-gdgds   IPv4   80   10.244.0.23,10.244.0.24
```

## Lab 2 – Environment variables and DNS
```bash
kubectl exec <old-pod> -- printenv | grep SERVICE      # only KUBERNETES_SERVICE_* (Pod is older than the Service)
kubectl scale deployment my-nginx --replicas=0; kubectl scale deployment my-nginx --replicas=2;
kubectl exec <new-pod> -- printenv | grep SERVICE
#   MY_NGINX_SERVICE_HOST=10.98.155.117   MY_NGINX_SERVICE_PORT=80   KUBERNETES_SERVICE_HOST=10.96.0.1 …
kubectl get services kube-dns --namespace=kube-system  # kube-dns   ClusterIP   10.96.0.10   53/UDP,53/TCP,9153/TCP
kubectl run curl --image=busybox:1.28 -i --tty --rm
/ # nslookup my-nginx
#   Server:    10.96.0.10   Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
#   Name:      my-nginx     Address 1: 10.98.155.117 my-nginx.default.svc.cluster.local
```

## Lab 3 – Securing the Service
```bash
./convert-images.sh                                   # NOT from the docs: schema-1 images → loaded into minikube
openssl req -x509 -noenc -days 365 -newkey rsa:2048 -keyout /tmp/nginx.key -out /tmp/nginx.crt -subj "/CN=my-nginx/O=my-nginx"
cat /tmp/nginx.crt | base64 | tr -d '\n'              # → tls.crt in nginxsecrets.yaml (from nginxsecrets.template.yaml)
cat /tmp/nginx.key | base64 | tr -d '\n'              # → tls.key
kubectl apply -f nginxsecrets.yaml                    # secret/nginxsecret created   (kubernetes.io/tls, DATA 2)
#   (shortcut, same result: kubectl create secret tls nginxsecret --key /tmp/nginx.key --cert /tmp/nginx.crt)
kubectl create configmap nginxconfigmap --from-file=default.conf
kubectl delete deployments,svc my-nginx; kubectl create -f ./nginx-secure-app.yaml
kubectl get pods -l run=my-nginx -o custom-columns=POD_IP:.status.podIPs      # [map[ip:10.244.0.28]]
minikube ssh -- curl -k https://10.244.0.28           # <h1>Welcome to nginx!</h1>   (docs: "node $ curl -k https://<pod IP>")
kubectl apply -f ./curlpod.yaml
kubectl get pods -l app=curlpod                       # curl-deployment-7db75cbd8c-8nz4g   1/1 Running
kubectl exec curl-deployment-7db75cbd8c-8nz4g -- curl https://my-nginx --cacert /etc/nginx/ssl/tls.crt
#   <title>Welcome to nginx!</title>                  <- verified against the cert from the same Secret
```

## Lab 4 – Exposing the Service
```bash
kubectl get svc my-nginx -o yaml | grep nodePort -C 5
#   - name: http   nodePort: 30334   port: 8080   targetPort: 80
#   - name: https  nodePort: 30755   port: 443    targetPort: 443
kubectl get nodes -o yaml | grep ExternalIP -C 1      # (nothing on minikube) → use $(minikube ip) = 192.168.58.2
curl https://192.168.58.2:30755 -k                    # <h1>Welcome to nginx!</h1>
kubectl edit svc my-nginx                             # type: NodePort → LoadBalancer
#   non-interactive: kubectl patch svc my-nginx -p '{"spec":{"type":"LoadBalancer"}}'
#   NOT from the docs: ../../../tasks/access-application-cluster/create-external-load-balancer/run-fake-lb.sh start
kubectl get svc my-nginx
#   my-nginx   LoadBalancer   10.107.182.242   203.0.113.200   8080:30334/TCP,443:30755/TCP
kubectl describe service my-nginx                     # LoadBalancer Ingress:  203.0.113.200 (VIP)
minikube ssh -- curl -sk https://203.0.113.200        # <h1>Welcome to nginx!</h1>
```

## Cleanup
```bash
./cleanup.sh      # Service (while the fake LB runs), Deployments my-nginx + curl-deployment, Secret, ConfigMap; stop fake LB
```
