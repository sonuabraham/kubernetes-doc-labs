# Configure a Pod to Use a ConfigMap – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/

> Runs on the default **minikube** cluster, in the `default` namespace as in the docs. Run everything **from this folder**.
> The docs' `wget` downloads are already in [configure-pod-container/configmap/](configure-pod-container/configmap/), the same relative path the docs use.
> Docs examples (**verbatim**): [configmaps.yaml](configmaps.yaml), [configmap-multikeys.yaml](configmap-multikeys.yaml),
> `pod-*.yaml` (6 Pods), [optional-env.yaml](optional-env.yaml), [optional-volume.yaml](optional-volume.yaml).
> Not from the docs: `optional-*-fixed.yaml`, [restrictions.yaml](restrictions.yaml), [update-demo.yaml](update-demo.yaml).
>
> **Docs problems found:**
> 1. The two "Optional ConfigMaps" Pods use `gcr.io/google_containers/busybox`, which **no longer pulls** (`ImagePullBackOff`). The `-fixed` files swap in `registry.k8s.io/busybox:1.27.2`.
> 2. Following the page in order, `kubectl create configmap game-config-2 … --from-file=…ui.properties` fails (`already exists`) because the single-file `game-config-2` was never deleted. The same happens for `kubectl create -f configmaps.yaml`, whose `special-config` still exists from the previous step.
> 3. The interim cleanup deletes `env-config`, which doesn't exist yet (`NotFound`), and never deletes `special-config-2-*`.
> 4. Keys like `1badkey` are **no longer skipped** by `envFrom`. `RelaxedEnvironmentVariableValidation` is GA, so there's no `InvalidEnvironmentVariableNames` event.
> 5. Mounted ConfigMap updates are bound by the kubelet **sync period** (≤ 60 s here). The "+ cache TTL" part doesn't apply with the default `Watch` change detection.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Create from** | `--from-file=<dir>` (one key per regular file), `--from-file=[key=]file`, `--from-env-file` (one key per `VAR=VAL` line; quotes are kept), `--from-literal`, or a kustomize `configMapGenerator`, which adds a **content-hash suffix**. |
| **Consume as env** | `env[].valueFrom.configMapKeyRef` (one key), `envFrom.configMapRef` (all keys), `$(VAR)` in `command`/`args`. Read **once at container start**. |
| **Consume as files** | A `configMap` volume, one file per key (`items` select/rename them). Updated **live**, except `subPath` mounts. The mount hides what the image had in that directory. |
| **optional: true** | Missing ConfigMap/key gives an empty env / empty dir instead of `CreateContainerConfigError`. |
| **binaryData / immutable** | Non-UTF-8 input goes to `binaryData`. `immutable: true` freezes the data (and saves kubelet watches). |
| **Same namespace** | Pods can only reference ConfigMaps in their own namespace. Static Pods can't use them at all. |

---

## Step 0
```bash
cd tasks/configure-pod-container/configure-pod-configmap
run(){ kubectl create -f $1 >/dev/null; kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/dapi-test-pod --timeout=60s >/dev/null \
       || kubectl get pod dapi-test-pod; kubectl logs dapi-test-pod | grep -E "${2:-.}"; kubectl delete pod dapi-test-pod --now >/dev/null; }
```

## Lab 1 – Create ConfigMaps (docs)
```bash
kubectl create configmap game-config --from-file=configure-pod-container/configmap/
kubectl get cm game-config -o json | jq -c '.data|keys'
#   ["game-env-file.properties","game.properties","ui-env-file.properties","ui.properties"]
```
The docs show only two keys because they download the env files *later*. A directory source takes **every** regular file in it.
```bash
kubectl create configmap game-config-2 --from-file=configure-pod-container/configmap/game.properties
kubectl create configmap game-config-2 --from-file=configure-pod-container/configmap/game.properties \
  --from-file=configure-pod-container/configmap/ui.properties
#   error: failed to create configmap: configmaps "game-config-2" already exists     <- docs problem 2
kubectl delete cm game-config-2; # …and run the second command again
kubectl get cm game-config-2 -o json | jq -c '.data|keys'          # ["game.properties","ui.properties"]

kubectl create configmap game-config-env-file --from-env-file=configure-pod-container/configmap/game-env-file.properties
kubectl get configmap game-config-env-file -o json | jq -c .data
#   {"allowed":"\"true\"","enemies":"aliens","lives":"3"}           <- the quotes are part of the value
kubectl create configmap config-multi-env-files \
  --from-env-file=configure-pod-container/configmap/game-env-file.properties \
  --from-env-file=configure-pod-container/configmap/ui-env-file.properties
kubectl get configmap config-multi-env-files -o json | jq -c .data
#   {"allowed":"\"true\"","color":"purple","enemies":"aliens","how":"fairlyNice","lives":"3","textmode":"true"}
kubectl create configmap game-config-3 --from-file=game-special-key=configure-pod-container/configmap/game.properties
kubectl get cm game-config-3 -o json | jq -c '.data|keys'          # ["game-special-key"]
kubectl create configmap special-config --from-literal=special.how=very --from-literal=special.type=charm
kubectl get cm special-config -o json | jq -c .data                # {"special.how":"very","special.type":"charm"}
```

## Lab 2 – Generators (docs)
Run the three `cat <<EOF >./kustomization.yaml … EOF` + `kubectl apply -k .` blocks from the page here:
```
configmap/game-config-4-tbg7c4gc77 created
configmap/game-config-5-tfhf8f4fkf created
configmap/special-config-2-2b86tk8fhm created
```
Change a literal (`special.type=strange`) and apply again: `configmap/special-config-2-dk7hg266tc created`. The new
content gets a **new name**, and the old ConfigMap stays. That's how a Deployment referencing it via kustomize rolls out
config changes.
```bash
kubectl delete configmap special-config
kubectl delete configmap env-config            # Error from server (NotFound) - docs problem 3
kubectl delete configmap -l 'game-config in (config-4,config-5)'
```

## Lab 3 – Environment variables (docs)
```bash
kubectl create configmap special-config --from-literal=special.how=very
run pod-single-configmap-env-variable.yaml SPECIAL        # SPECIAL_LEVEL_KEY=very
kubectl delete configmap special-config                   # docs problem 2: otherwise the next create fails
kubectl create -f configmaps.yaml
run pod-multiple-configmap-env-variable.yaml 'SPECIAL|LOG' # LOG_LEVEL=INFO  SPECIAL_LEVEL_KEY=very
kubectl delete configmap special-config env-config
kubectl create -f configmap-multikeys.yaml
run pod-configmap-envFrom.yaml SPECIAL                     # SPECIAL_LEVEL=very  SPECIAL_TYPE=charm
run pod-configmap-env-var-valueFrom.yaml                   # very charm
```

## Lab 4 – Volumes (docs)
```bash
run pod-configmap-volume.yaml                # SPECIAL_LEVEL  SPECIAL_TYPE
run pod-configmap-volume-specific-key.yaml   # very
```

## Lab 5 – Optional references (docs, with the image fixed)
```bash
kubectl create -f optional-env.yaml; sleep 20; kubectl get pod dapi-test-pod     # ImagePullBackOff - docs problem 1
kubectl delete pod dapi-test-pod --now
run optional-env-fixed.yaml SPECIAL                                       # (nothing: no ConfigMap a-config)
kubectl create configmap a-config --from-literal=other=1
run optional-env-fixed.yaml SPECIAL                                       # (nothing: no key akey)
kubectl delete cm a-config; kubectl create configmap a-config --from-literal=akey=hello
run optional-env-fixed.yaml SPECIAL                                       # SPECIAL_LEVEL_KEY=hello
run optional-volume-fixed.yaml                                            # (empty listing, but /etc/config exists)
```

## Lab 6 – Restrictions (not from the docs)
```bash
kubectl apply -f restrictions.yaml
kubectl get pod missing-cm bad-keys
#   missing-cm   0/1   CreateContainerConfigError       <- non-optional ref to a missing ConfigMap
#   bad-keys     0/1   Completed
kubectl get pod missing-cm -o jsonpath='{.status.containerStatuses[0].state.waiting.message}{"\n"}'
#   configmap "does-not-exist" not found
kubectl logs bad-keys
#   good_key=z
#   1badkey=x            <- accepted: docs problem 4
#   2alsobad=y
kubectl get --raw /metrics | grep 'name="RelaxedEnvironmentVariableValidation"'     # stage="" 1 (GA)
```

## Lab 7 – Live updates: volume vs subPath vs env (not from the docs)
```bash
kubectl apply -f update-demo.yaml
kubectl patch cm live-config -p '{"data":{"mode":"v2"}}'
# poll: kubectl exec update-demo -- cat /etc/config/mode
kubectl exec update-demo -- sh -c 'echo "volume=$(cat /etc/config/mode) subPath=$(cat /etc/subpath-mode) env=$MODE"'
#   volume=v2 subPath=v1 env=v1
```
| Update | Time until the file changed |
|---|---|
| v1 → v2 | 2 s (the Pod's sync happened to be due) |
| v3 → v4, no help | **60 s** (the next periodic sync) |
| v2 → v3 + `kubectl annotate pod update-demo refresh=$(date +%s) --overwrite` | **0 s**: changing the Pod triggers an immediate sync |
```bash
kubectl get --raw /api/v1/nodes/minikube/proxy/configz | jq -c '.kubeletconfig|{configMapAndSecretChangeDetectionStrategy, syncFrequency}'
#   {"configMapAndSecretChangeDetectionStrategy":"Watch","syncFrequency":"1m0s"}
```

## Lab 8 – binaryData and immutable (not from the docs)
```bash
printf '\x89PNG\x00\xff' > /tmp/logo.bin
kubectl create configmap binary-demo --from-file=logo.png=/tmp/logo.bin --from-literal=text=hello
kubectl get configmap -o jsonpath='{.binaryData}' binary-demo      # {"logo.png":"iVBORwD/"}   (base64)
kubectl get configmap -o jsonpath='{.data}' binary-demo            # {"text":"hello"}
kubectl create configmap frozen --from-literal=a=1 --dry-run=client -o json | jq '.immutable=true' | kubectl apply -f -
kubectl patch cm frozen -p '{"data":{"a":"2"}}'
#   The ConfigMap "frozen" is invalid: data: Forbidden: field is immutable when `immutable` is set
```

## Useful commands
```bash
kubectl describe configmaps <name>
kubectl get configmap <name> -o yaml
kubectl create configmap <name> --from-file=… --dry-run=client -o yaml     # preview
```

## Cleanup
```bash
./cleanup.sh      # the docs' cleanup + the extra objects + kustomization.yaml
```
