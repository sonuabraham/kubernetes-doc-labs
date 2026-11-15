# Define a Command and Arguments for a Container – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/

> Runs on the default **minikube** cluster, `default` namespace. Files: [commands.yaml](commands.yaml) (docs, **verbatim**),
> [snippets.yaml](snippets.yaml) (the docs' two snippets as Pods + two extra Pods, not from the docs).

## Key ideas (read first)

| Pod spec | Image | Result |
|---|---|---|
| `command` | `ENTRYPOINT` | replaced |
| `args` | `CMD` | replaced |
| only `args` | | image ENTRYPOINT + your args |
| only `command` | | your command, image CMD ignored |
| `$(VAR)` in command/args | | expanded by **Kubernetes** from the container's env. `$$(VAR)` stays literal. Unknown names stay as written. |
| `$VAR`, `${VAR}` | | **not** expanded (no shell). Use `sh -c` for shell features. |
| immutable | | can't change after the Pod is created |

---

## Step 0
```bash
cd tasks/inject-data-application/define-command-argument-container
```

## Lab 1 – command + args (docs)
```bash
kubectl apply -f commands.yaml                 # command: ["printenv"], args: ["HOSTNAME", "KUBERNETES_PORT"]
kubectl get pods                               # command-demo   0/1   Completed
kubectl logs command-demo
#   command-demo
#   tcp://10.96.0.1:443                        <- this cluster's kubernetes Service IP (docs: 10.3.240.1)
```

## Lab 2 – Environment variables in args, and a shell (docs snippets)
```bash
kubectl apply -f snippets.yaml
kubectl logs env-arg-demo                      # hello world            <- args: ["$(MESSAGE)"]
kubectl logs shell-demo                        # hello (every 10 s)     <- command: ["/bin/sh"], args: ["-c", "while true; …"]
```

## Lab 3 – What exactly gets expanded (not from the docs)
```bash
kubectl logs no-paren-demo
#   $MESSAGE ${MESSAGE} hello world $(MESSAGE) $(UNDEFINED)
#   ^ shell syntax: untouched     ^ $(MESSAGE)  ^ $$(MESSAGE) escaped   ^ unknown variable left as is
kubectl logs args-only-demo | tail -2
#   /docker-entrypoint.sh: Configuration complete; ready for start up      <- nginx image ENTRYPOINT still ran …
#   nginx version: nginx/1.27.5                                            <- … with our args ["nginx", "-v"]
```

## Useful commands
```bash
kubectl get pod <p> -o jsonpath='{.spec.containers[0].command} {.spec.containers[0].args}'
docker image inspect <image> --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'      # the image defaults (locally)
```

## Cleanup
```bash
./cleanup.sh
```
