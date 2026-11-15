# Get a Shell to a Running Container – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-application/get-shell-running-container/

> Runs on the default **minikube** cluster, `default` namespace. Files: [shell-demo.yaml](shell-demo.yaml) (docs, **verbatim**).
> Not from the docs: [my-pod.yaml](my-pod.yaml) (the docs' two-container example `main-app` / `helper-app`).
> The interactive part works as in the docs (`kubectl exec --stdin --tty shell-demo -- /bin/bash`). The outputs below come from
> the equivalent one-shot `kubectl exec` commands.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `kubectl exec <pod> -- <cmd>` | run a command in a container. `--` separates kubectl's flags from the command. |
| `-i` / `--stdin`, `-t` / `--tty` | keep stdin open / allocate a terminal. `-it` gives an interactive shell. `-i` alone lets you **pipe** a script in. |
| `-c <container>` | choose the container. Without it you get the `kubectl.kubernetes.io/default-container` annotation, or else the first container. |
| Needs tools in the image | No shell or `ps`? Use `kubectl debug` ([debug-running-pod](../debug-running-pod/)). |
| `shell-demo` uses **`hostNetwork: true`** | nginx listens on the **node's** port 80, the Pod IP is the node IP, and its hostname is the node's. |

---

## Step 0
```bash
cd tasks/debug/debug-application/get-shell-running-container
kubectl apply -f shell-demo.yaml
kubectl get pod shell-demo -o wide          # Running   IP 192.168.58.2  = the minikube node (hostNetwork)
```

## Lab 1 – A shell in the container (docs)
```bash
kubectl exec --stdin --tty shell-demo -- /bin/bash
# inside: ls /   cat /proc/mounts   apt-get update && apt-get install -y procps && ps aux   …   exit
```
The same as one-shot commands:
```bash
kubectl exec shell-demo -- ls /                        # bin boot dev docker-entrypoint.d … var
kubectl exec shell-demo -- cat /proc/1/cmdline | tr '\0' ' '     # nginx: master process nginx -g daemon off;
```

## Lab 2 – Write the root page (docs)
```bash
kubectl exec shell-demo -- sh -c "echo 'Hello shell demo' > /usr/share/nginx/html/index.html"
kubectl exec shell-demo -- curl -s http://localhost/        # Hello shell demo   (curl is in the nginx image now)
minikube ssh -- curl -s http://localhost/                    # Hello shell demo   <- the NODE's port 80
kubectl exec shell-demo -- cat /proc/1/mounts | grep nginx/html
#   /dev/nvme0n1p5 /usr/share/nginx/html ext4 rw,relatime …   <- the emptyDir, on the node's disk
```

## Lab 3 – Individual commands (docs)
```bash
kubectl exec shell-demo -- env | grep -E 'HOSTNAME|KUBERNETES_SERVICE_HOST'
#   HOSTNAME=minikube                <- hostNetwork: the node's hostname
#   KUBERNETES_SERVICE_HOST=10.96.0.1
kubectl exec shell-demo -- ps aux
#   … exec: "ps": executable file not found in $PATH        <- the docs' example needs procps installed first (Lab 1)
kubectl exec shell-demo -- ls /
kubectl exec shell-demo -- cat /proc/1/mounts
```

## Lab 4 – More than one container (docs `my-pod`)
```bash
kubectl apply -f my-pod.yaml          # main-app (nginx) + helper-app (busybox), default-container: helper-app
kubectl exec my-pod -- ls /usr/share/nginx
#   ls: /usr/share/nginx: No such file or directory      <- landed in helper-app (the annotation)
printf 'head -1 /etc/os-release\nexit\n' | kubectl exec -i my-pod --container main-app -- /bin/bash
#   PRETTY_NAME="Debian GNU/Linux 13 (trixie)"          <- main-app, with a script piped to stdin (-i without -t)
```

## Lab 5 – The cost of `hostNetwork` (not from the docs)
```bash
sed 's/name: shell-demo/name: shell-demo-2/' shell-demo.yaml | kubectl apply -f -
kubectl get pod shell-demo-2                    # Error / CrashLoopBackOff
kubectl logs shell-demo-2 | grep bind
#   [emerg] 1#1: bind() to 0.0.0.0:80 failed (98: Address already in use)
```
Two hostNetwork Pods on one node can't use the same port. The scheduler only prevents this for declared `hostPort`s.

## Useful commands
```bash
kubectl exec -it <pod> [-c <container>] -- sh
kubectl exec <pod> -- sh -c '<pipeline with | and >>'      # shell features need a shell
kubectl get pod <pod> -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/default-container}'
```

## Cleanup
```bash
./cleanup.sh
```
