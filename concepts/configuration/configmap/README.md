# ConfigMaps – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/configuration/configmap/

> Docs manifests are **verbatim**: [01-game-demo-configmap.yaml](01-game-demo-configmap.yaml), [configure-pod.yaml](configure-pod.yaml), [02-mypod-volume.yaml](02-mypod-volume.yaml), [03-myconfigmap.yaml](03-myconfigmap.yaml), [env-configmap.yaml](env-configmap.yaml), [04-env-configmap-keyref.yaml](04-env-configmap-keyref.yaml), [05-immutable-excerpt.yaml](05-immutable-excerpt.yaml) (literal `...`). The page has **two Pods named `env-configmap`**, so the second runs in namespace `cm-demo2`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **ConfigMap** | Non-confidential key/value config, decoupled from the image. **No secrecy** (use Secrets). Max **1 MiB**. |
| **data / binaryData** | UTF-8 strings / base64 bytes. Keys: alphanumerics, `-`, `_`, `.`. Property-like (`lives: "3"`) or file-like (`game.properties: \|`). |
| **Consume it 4 ways** | Container **command/args**, **env vars** (`configMapKeyRef`, `envFrom`), **files** in a volume, or the **API** (an app reads it, even from other namespaces with RBAC). |
| **Same namespace** | A Pod can only reference ConfigMaps in its own namespace. Static Pods can't reference them at all. |
| **Updates** | Volume files update **eventually** (kubelet sync period + cache TTL, atomic `..data` swap). **Env vars never** update, and **subPath** mounts don't either: restart the Pod. |
| **optional** | `optional: true` → a missing ConfigMap/key gives an empty volume / unset var instead of a stuck Pod. |
| **immutable: true** | Data can't change, and neither can the flag. It protects against accidents and lets kubelets stop watching (scales better). Delete and recreate to change it. |

---

## Step 1
```bash
cd concepts/configuration/configmap
kubectl create namespace cm-demo ; kubectl create namespace cm-demo2
kubectl apply -n cm-demo  -f 01-game-demo-configmap.yaml -f configure-pod.yaml -f 03-myconfigmap.yaml -f 02-mypod-volume.yaml -f env-configmap.yaml
kubectl apply -n cm-demo2 -f 03-myconfigmap.yaml -f 04-env-configmap-keyref.yaml
```

## Lab 1 – Env vars + selected keys as files (docs `configmap-demo-pod`)
```bash
kubectl exec configmap-demo-pod -n cm-demo -- sh -c 'env | grep -E "PLAYER|UI_PROP"; ls /config'
#   PLAYER_INITIAL_LIVES=3                      <- env name differs from the key (player_initial_lives)
#   UI_PROPERTIES_FILE_NAME=user-interface.properties
#   game.properties  user-interface.properties  <- only the 2 "items"; the property-like keys aren't files
```

## Lab 2 – All keys as files (docs `mypod`)
```bash
kubectl exec mypod -n cm-demo -- ls -la /etc/foo
#   ..2026_11_12_00_13_10.642084914/
#   ..data -> ..2026_11_12_…                   <- swapped atomically on update
#   access_level -> ..data/access_level
#   username -> ..data/username
```

## Lab 3 – envFrom and configMapKeyRef (docs `env-configmap` ×2)
```bash
kubectl logs env-configmap -n cm-demo | grep -E '^(username|access_level)='
#   access_level=1
#   username=k8s-admin
kubectl exec env-configmap -n cm-demo2 -- sh -c 'echo $CONFIGMAP_USERNAME'      # k8s-admin
```
The docs show `username: "k8s-admin"`. `printenv` really prints `name=value`.

## Lab 4 – Updates: volume yes, env and subPath no
```bash
kubectl apply -n cm-demo -f 06-subpath-pod.yaml
kubectl patch cm game-demo -n cm-demo --type=merge -p '{"data":{"player_initial_lives":"99","game.properties":"enemy.types=dragons\nplayer.maximum-lives=9\n"}}'
until kubectl exec configmap-demo-pod -n cm-demo -- grep -q dragons /config/game.properties; do sleep 2; done     # took 61s here
kubectl exec configmap-demo-pod -n cm-demo -- sh -c 'echo $PLAYER_INITIAL_LIVES'       # 3      <- env frozen at container start
kubectl exec subpath-pod -n cm-demo -- sh -c 'head -1 /config/game.properties; head -1 /etc/game.properties'
#   enemy.types=dragons              <- volume mount: updated
#   enemy.types=aliens,monsters      <- subPath mount of the SAME key: never updated
```

## Lab 5 – Immutable
```bash
kubectl apply -n cm-demo -f 07-immutable.yaml          # the docs' excerpt, filled in
kubectl patch cm frozen-config -n cm-demo --type=merge -p '{"data":{"mode":"debug"}}'
#   data: Forbidden: field is immutable when `immutable` is set
kubectl patch cm frozen-config -n cm-demo --type=merge -p '{"immutable":false}'
#   immutable: Forbidden: field is immutable when `immutable` is set           <- one-way switch
```

## Lab 6 – Missing ConfigMaps and optional
```bash
kubectl apply -n cm-demo -f 08-optional.yaml
kubectl get pod needs-missing -n cm-demo                # CreateContainerConfigError: configmap "does-not-exist" not found
kubectl logs optional-missing -n cm-demo                # COLOR=[]  and 0 files  - started fine
```
Create `does-not-exist` later and `needs-missing` starts by itself. The kubelet keeps retrying.

## Lab 7 – Keys, env names, size
```bash
kubectl apply -n cm-demo -f 09-envfrom-keys.yaml ; kubectl logs envfrom-keys -n cm-demo
#   1starts-with-digit=4  dotted.key=3  with-dash=2  GOOD_KEY=1  + the same with CFG_ prefix
```
Every key became a variable, even ones that aren't C identifiers: since **RelaxedEnvironmentVariableValidation** (GA) env names may be any printable ASCII except `=`. Older clusters skipped such keys with an `InvalidEnvironmentVariableNames` event. Your **shell** still can't `$expand` `with-dash`, though.
```bash
kubectl create cm bad-key -n cm-demo --from-literal='a/b=1'
#   "a/b" is not a valid key name for a ConfigMap: ... alphanumeric characters, '-', '_' or '.'
head -c 1100000 /dev/zero | tr '\0' x > big.txt ; kubectl create cm too-big -n cm-demo --from-file=big.txt ; rm big.txt
#   ConfigMap "too-big" is invalid: []: Too long: may not be more than 1048576 bytes
```

---

## Useful commands
```bash
kubectl create configmap <n> --from-literal=k=v --from-file=<file> --from-env-file=<.env>
kubectl get cm <n> -o yaml
kubectl create cm <n> --from-file=... --dry-run=client -o yaml | kubectl apply -f -     # "update from files"
```

## Cleanup
```bash
./cleanup.sh
```
