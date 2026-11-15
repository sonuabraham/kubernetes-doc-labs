# Define Environment Variables for a Container – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [envars.yaml](envars.yaml),
> [print-greeting.yaml](print-greeting.yaml) (the inline example).
>
> **Found:** (1) `kubectl exec envar-demo -- printenv` fails: `gcr.io/google-samples/hello-app:2.0` contains no `printenv` (or shell).
> Lab 1 reads the environment with a debug container instead. (2) `print-greeting` has no `restartPolicy`, so after printing it is restarted
> again and again and ends up in `CrashLoopBackOff`. The output is right, but the Pod looks broken.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `env` | name/value pairs, or `valueFrom` (ConfigMap/Secret key, downward API) |
| `envFrom` | every key of a ConfigMap/Secret, optionally with a `prefix` (see [configure-pod-configmap](../../configure-pod-container/configure-pod-configmap/)) |
| override | Pod env beats the image's `ENV` |
| references | `$(OTHER)` to earlier variables (see [define-interdependent-environment-variables](../define-interdependent-environment-variables/)) |
| names | any printable ASCII except `=` (`RelaxedEnvironmentVariableValidation`, GA) |

---

## Step 0
```bash
cd tasks/inject-data-application/define-environment-variable-container
```

## Lab 1 – The docs' Pod
```bash
kubectl apply -f envars.yaml
kubectl get pods -l purpose=demonstrate-envars          # envar-demo   1/1   Running
kubectl exec envar-demo -- printenv
#   error: … failed to exec in container: … exec: "printenv": executable file not found in $PATH
kubectl debug envar-demo --image=busybox:1.36 --target=envar-demo-container --container=dbg --profile=general -q -- \
  sh -c 'sleep 1; tr "\0" "\n" < /proc/1/environ | grep -E "DEMO_|HOSTNAME|KUBERNETES_SERVICE_HOST"'
kubectl logs envar-demo -c dbg
#   HOSTNAME=envar-demo
#   DEMO_GREETING=Hello from the environment
#   DEMO_FAREWELL=Such a sweet sorrow
#   KUBERNETES_SERVICE_HOST=10.96.0.1
```
`--profile=general` is needed: the app runs as uid 65532, and only a root process with `SYS_PTRACE` may read another user's
`/proc/<pid>/environ` (`--profile=legacy` gives `Permission denied`). See [share-process-namespace](../../configure-pod-container/share-process-namespace/).

## Lab 2 – Variables used in args (docs inline example)
```bash
kubectl apply -f print-greeting.yaml
kubectl logs print-greeting                     # Warm greetings to The Most Honorable Kubernetes
kubectl get pod print-greeting                  # … CrashLoopBackOff   <- restartPolicy Always for a one-shot command
```
Add `restartPolicy: Never` (or `OnFailure`) for Pods that are meant to run once.

## Lab 3 – Overrides and names (not from the docs)
```bash
kubectl run envtest --image=nginx:1.27 --restart=Never --env=NGINX_VERSION=overridden --command -- sh -c 'echo $NGINX_VERSION'
kubectl logs envtest                            # overridden      <- the image sets NGINX_VERSION=1.27.x; the Pod value wins
kubectl run oddname --image=busybox:1.36 --dry-run=server -o name \
  --overrides='{"spec":{"containers":[{"name":"oddname","image":"busybox:1.36","env":[{"name":"MY VAR.with-chars!","value":"x"}]}]}}'
#   pod/oddname          <- spaces, dots, "!" are allowed now
… "env":[{"name":"A=B","value":"x"}] …
#   … env[0].name: Invalid value: "A=B": a valid environment variable name must consist only of printable ASCII characters other than '='
```

## Cleanup
```bash
./cleanup.sh
```
