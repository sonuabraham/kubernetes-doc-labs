# Ingress Controllers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/

> **The Ingress API is frozen.** It's GA and won't be removed, but gets no new features. The project recommends **Gateway API** (`../gateway-api`). The Ingress resource itself is covered in `../ingress`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Ingress controller** | The program that makes Ingress objects do something. It **watches** Ingresses of its class, **configures a proxy/LB** (nginx, Envoy, HAProxy, a cloud LB…), and **publishes the address** in `status.loadBalancer`. Not started with the cluster: you install one. |
| **Project-maintained** | AWS Load Balancer Controller, GCE. Plus a long third-party list (Contour, Traefik, HAProxy, Kong, Istio, Cilium, NGINX…). ingress-nginx was retired in March 2026. |
| **IngressClass** | Cluster-scoped. `spec.controller` names the controller implementation. Ingresses pick one with `spec.ingressClassName`. |
| **Multiple controllers** | Run as many as you like, one IngressClass each. Each controller **ignores** other classes. |
| **Default class** | Annotation `ingressclass.kubernetes.io/is-default-class: "true"`. Ingresses created **without** a class get it filled in at admission. Have exactly **one** default. |
| **No controller** | An Ingress whose class nobody implements is accepted by the API and does **nothing** (no ADDRESS). |

## The demo app
To see what a controller actually does, this lab runs a **toy ingress controller** you can read in a minute:
| File | What |
|---|---|
| [00-toy-setup.yaml](00-toy-setup.yaml) | IngressClass `toy` (controller `example.com/toy-ingress-controller`), its data plane (nginx `toy-proxy` reading ConfigMap `toy-proxy-conf`), backends `blue` and `green` |
| [toy-controller.sh](toy-controller.sh) | The control loop: Ingresses of class `toy` → nginx `server`/`location` blocks → ConfigMap → reload the proxy → write the proxy IP to `status.loadBalancer` |
| [01-ingresses.yaml](01-ingresses.yaml) | `toy-blue`, `toy-green` (class toy) and `orphan` (class `nobody`) |
| [req.sh](req.sh) | `./req.sh <host>` sends a request through the toy proxy with that Host header |

---

## Lab 1 – Run the controller
```bash
cd concepts/services-networking/ingress-controllers
kubectl apply -f 00-toy-setup.yaml
kubectl wait --for=condition=Available deploy --all -n ingressctl-demo --timeout=120s
kubectl apply -f 01-ingresses.yaml
./toy-controller.sh                 # terminal 1 - keep it running
#   08:51:01 config changed -> proxy reloaded:
#       server { listen 80; server_name blue.example.com;
#         location / { proxy_pass http://blue.ingressctl-demo.svc.cluster.local:80; }
#       }
#       server { listen 80; server_name green.example.com; ... }
```

## Lab 2 – Status and routing
```bash
kubectl get ingress -n ingressctl-demo
#   orphan      nobody   lost.example.com                    <- no controller for class "nobody": no ADDRESS, ever
#   toy-blue    toy      blue.example.com    10.107.94.123   <- address published by the toy controller
#   toy-green   toy      green.example.com   10.107.94.123
./req.sh blue.example.com           # hello from blue
./req.sh green.example.com          # hello from green
./req.sh nope.example.com           # 404 Not Found   (default_server: "toy: no route")
```
Change a host in `01-ingresses.yaml` and re-apply. Terminal 1 shows the regenerated config, and the route follows. That's all an ingress controller is: a controller loop plus a proxy.

## Lab 3 – Several controllers, one cluster
```bash
minikube addons enable ingress                       # adds the ingress-nginx controller + IngressClass "nginx"
kubectl get ingressclass
#   nginx   k8s.io/ingress-nginx
#   toy     example.com/toy-ingress-controller
kubectl get ingress -n ingressctl-demo -o custom-columns=NAME:.metadata.name,CLASS:.spec.ingressClassName,ADDRESS:.status.loadBalancer.ingress[0].ip
```
Each controller only touches Ingresses of **its** class: ingress-nginx ignores `toy-*`, and the toy controller ignores anything not `toy`. (`minikube addons disable ingress` afterwards. Full ingress-nginx exercises are in `../ingress`.)

## Lab 4 – The default IngressClass
```bash
kubectl annotate ingressclass toy ingressclass.kubernetes.io/is-default-class=true
kubectl create ingress noclass -n ingressctl-demo --rule="x.example.com/*=blue:80"
kubectl get ingress noclass -n ingressctl-demo -o jsonpath='class={.spec.ingressClassName}{"\n"}'     # class=toy  (filled in at admission)
```
Mark two classes as default and class-less Ingresses are rejected (see `../ingress`, Lab 9).

---

## Useful commands
```bash
kubectl get ingressclass
kubectl get ingress -A -o custom-columns=NAME:.metadata.name,CLASS:.spec.ingressClassName,ADDRESS:.status.loadBalancer.ingress[0].ip
kubectl describe ingress <name>
```

## Cleanup
```bash
./cleanup.sh       # namespace + IngressClass toy (and stop toy-controller.sh with Ctrl-C)
```
