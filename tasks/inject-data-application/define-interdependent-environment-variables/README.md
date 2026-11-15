# Define Dependent Environment Variables – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/inject-data-application/define-interdependent-environment-variables/

> Runs on the default **minikube** cluster, `default` namespace. Files: [dependent-envars.yaml](dependent-envars.yaml) (docs, **verbatim**),
> [reference-sources.yaml](reference-sources.yaml) (not from the docs).

## Key ideas (read first)

| Rule | Example |
|---|---|
| `$(NAME)` in an env `value` is replaced by the kubelet when the container starts | `SERVICE_ADDRESS=$(PROTOCOL)://…` |
| Only variables defined **earlier** count (in `env` order, after everything from `envFrom`) | `UNCHANGED_REFERENCE` is defined before `PROTOCOL`, so it stays `$(PROTOCOL)` |
| Unknown names stay literally | no error |
| `$$(NAME)` escapes, never expanded | `ESCAPED_REFERENCE` |

---

## Lab 1 – The docs' Pod
```bash
cd tasks/inject-data-application/define-interdependent-environment-variables
kubectl apply -f dependent-envars.yaml
kubectl logs pod/dependent-envars-demo
```
```
UNCHANGED_REFERENCE=$(PROTOCOL)://172.17.0.1:80      <- PROTOCOL defined later in the list
SERVICE_ADDRESS=https://172.17.0.1:80                <- all three defined earlier
ESCAPED_REFERENCE=$(PROTOCOL)://172.17.0.1:80        <- $$( … ) kept as $( … )
```

## Lab 2 – What else can be referenced? (not from the docs)
```bash
kubectl apply -f reference-sources.yaml
kubectl logs ref-sources-demo
```
```
USES_CM=cm=from-configmap                  <- a variable from envFrom (ConfigMap): visible to all env entries
USES_POD_IP=http://10.244.0.19:8080        <- a downward-API variable (status.podIP) defined earlier: works
A=a-then-$(B)                              <- circular: A can't see B (defined later) …
B=b-then-a-then-$(B)                       <- … B sees A's already-expanded value; no loop, no error
```
Circular references don't fail, they just produce half-expanded strings, which is why the docs say to avoid them.

## Cleanup
```bash
./cleanup.sh
```
