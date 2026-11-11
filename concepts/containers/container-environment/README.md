# Container Environment – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/containers/container-environment/

## Key ideas (read first)

| A container gets… | Details |
|---|---|
| **A filesystem** | The image plus any volumes mounted into it. |
| **Its hostname** | The **Pod name** (`hostname` command, `gethostname()`). |
| **Information about itself** | Pod name, namespace, node, IP… through the **downward API** (env vars or files). |
| **Environment variables** | From the Pod spec (`env`, `envFrom`) **and** the ones baked into the image (`ENV` in the Dockerfile). |
| **Cluster information** | For every Service that **existed when the container started**, in the same namespace (plus the control-plane `kubernetes` Service): `<NAME>_SERVICE_HOST`, `<NAME>_SERVICE_PORT` (+ Docker-link style `<NAME>_PORT_*`). Name is upper-cased, `-` becomes `_`. |
| **DNS** | Works for **all** Services, including ones created later. Prefer it over env vars. |
| `enableServiceLinks: false` | Turns off the per-Service variables (the `KUBERNETES_*` ones remain). Useful in namespaces with many Services. |

## The demo app
[00-foo-service.yaml](00-foo-service.yaml) is the docs' example: Service **`foo`** in front of Pods whose container is called **`bar`**, in namespace `env-demo`. [01-client.yaml](01-client.yaml) is a pod that shows every kind of environment. [02-late-service.yaml](02-late-service.yaml) is a Service created *after* the client. [03-no-service-links.yaml](03-no-service-links.yaml) is a pod with `enableServiceLinks: false`.

---

## Lab 1 – Hostname, downward API, spec and image env vars
```bash
cd concepts/containers/container-environment
kubectl apply -f 00-foo-service.yaml ; kubectl rollout status deploy/foo -n env-demo
kubectl apply -f 01-client.yaml ; kubectl wait --for=condition=Ready pod/client -n env-demo
kubectl exec client -n env-demo -- hostname                                   # client  (= pod name)
kubectl exec client -n env-demo -- sh -c 'env | sort | grep -E "^(GREETING|MY_|NGINX_VERSION)"'
```
Expected:
```
GREETING=hello from the pod spec      <- Pod spec
MY_NODE_NAME=minikube                 <- downward API
MY_POD_IP=10.244.0.102
MY_POD_NAME=client
MY_POD_NAMESPACE=env-demo
NGINX_VERSION=1.27.5                  <- baked into the image
```

## Lab 2 – Service environment variables (the docs' foo/bar example)
```bash
kubectl exec client -n env-demo -- sh -c 'env | sort | grep -E "^(FOO_|KUBERNETES_SERVICE)"'
kubectl get svc foo -n env-demo -o jsonpath='{.spec.clusterIP}{"\n"}'
```
Expected:
```
FOO_SERVICE_HOST=10.111.157.51        <- the docs' FOO_SERVICE_HOST / FOO_SERVICE_PORT
FOO_SERVICE_PORT=8080
FOO_SERVICE_PORT_HTTP=8080            <- one per NAMED port
FOO_PORT=tcp://10.111.157.51:8080     <- Docker-links compatible variants
FOO_PORT_8080_TCP_ADDR=10.111.157.51 ...
KUBERNETES_SERVICE_HOST=10.96.0.1     <- control-plane service, always there
```

## Lab 3 – Only Services that existed at start time
```bash
kubectl apply -f 02-late-service.yaml
kubectl exec client -n env-demo -- sh -c 'env | grep -c ^LATE_'                   # 0 - the env is fixed when the container starts
kubectl exec client -n env-demo -- getent hosts late.env-demo.svc.cluster.local   # resolves - DNS knows every Service
kubectl delete pod client -n env-demo ; kubectl apply -f 01-client.yaml ; kubectl wait --for=condition=Ready pod/client -n env-demo
kubectl exec client -n env-demo -- sh -c 'env | grep ^LATE_SERVICE_HOST'          # now present (new container)
```
This ordering dependency is why **DNS** is the recommended way to find Services.

## Lab 4 – Turning service links off
```bash
kubectl apply -f 03-no-service-links.yaml ; kubectl wait --for=condition=Ready pod/client-nolinks -n env-demo
kubectl exec client-nolinks -n env-demo -- sh -c 'env | sort | grep SERVICE_HOST'
#   KUBERNETES_SERVICE_HOST=10.96.0.1      <- only the control-plane one
```

---

## Useful commands
```bash
kubectl exec <pod> -- env | sort
kubectl set env pod/<pod> --list          # env as defined in the spec
kubectl explain pod.spec.enableServiceLinks
```

## Cleanup
```bash
./cleanup.sh
```
