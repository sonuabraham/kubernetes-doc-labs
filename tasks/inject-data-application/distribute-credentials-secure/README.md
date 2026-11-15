# Distribute Credentials Securely Using Secrets – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [secret.yaml](secret.yaml),
> [secret-pod.yaml](secret-pod.yaml), [pod-single-secret-env-variable.yaml](pod-single-secret-env-variable.yaml),
> [pod-multiple-secret-env-variable.yaml](pod-multiple-secret-env-variable.yaml), [pod-secret-envFrom.yaml](pod-secret-envFrom.yaml),
> and the inline examples [secret-items-pod.yaml](secret-items-pod.yaml), [secret-defaultmode-pod.yaml](secret-defaultmode-pod.yaml),
> [pod.yaml](pod.yaml), [sa-pod.yaml](sa-pod.yaml). Not from the docs: [pod-fixed.yaml](pod-fixed.yaml).
>
> **Found:**
> 1. `kubectl describe secret test-secret` shows `password: 12 bytes`, `username: 6 bytes`, not 13/7 as the page says (the page's numbers include a newline).
> 2. "Create a Secret directly with kubectl" fails with `already exists` if you already did the YAML step. Delete the Secret first; the page doesn't say so.
> 3. `pod.yaml` uses `image: myClientImage`, which is **not a valid image name** (uppercase), so both Pods end in `InvalidImageName`. Use [pod-fixed.yaml](pod-fixed.yaml) instead.
> 4. The service-account shortcut doesn't work as written. The text says `prod-user`, but the YAML uses `prod-db-client`, which doesn't exist (`Forbidden`).
>    Even with that ServiceAccount created, **no Secret is mounted**: ServiceAccounts don't inject arbitrary Secrets (only `imagePullSecrets`).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `data` vs. `--from-literal` | `data` values are base64 (`echo -n`!); `kubectl create secret` encodes for you |
| Volume | one file per key; `items` picks keys / renames paths; `defaultMode` / per-item `mode` (default `0644`) |
| `items` with a missing key | the volume can't be set up: Pod stays `ContainerCreating` |
| `secretKeyRef` / `envFrom.secretRef` | env vars; set **once** at container start |
| Updates | volume files are refreshed (seconds to a minute); env vars aren't (restart needed); `subPath` mounts aren't |
| JSON modes | JSON has no octal: `400` means decimal 400 = `0620`; use `256` for `0400` |

---

## Step 0
```bash
cd tasks/inject-data-application/distribute-credentials-secure
echo -n 'my-app' | base64           # bXktYXBw
echo -n '39528$vdg7Jb' | base64     # Mzk1MjgkdmRnN0pi
```

## Lab 1 – Secret + volume (docs)
```bash
kubectl apply -f secret.yaml
kubectl describe secret test-secret | sed -n '/Data/,$p'
#   password:  12 bytes        <- docs say 13
#   username:  6 bytes         <- docs say 7
kubectl create secret generic test-secret --from-literal='username=my-app' --from-literal='password=39528$vdg7Jb'
#   error: failed to create secret secrets "test-secret" already exists      <- it is the same Secret; skip or delete first
kubectl apply -f secret-pod.yaml
kubectl exec secret-test-pod -- sh -c 'ls /etc/secret-volume; cat /etc/secret-volume/username; echo; cat /etc/secret-volume/password; echo'
#   password  username
#   my-app
#   39528$vdg7Jb
```

## Lab 2 – `items`, `defaultMode` (docs inline examples) and a missing key
The docs' snippets use a Secret called `mysecret`, which the page never creates:
```bash
kubectl create secret generic mysecret --from-literal=username=my-app --from-literal='password=39528$vdg7Jb'
kubectl apply -f secret-items-pod.yaml
kubectl exec mypod -- sh -c 'ls -R /etc/foo; cat /etc/foo/my-group/my-username'
#   /etc/foo: my-group             <- no "password": only listed keys are projected
#   /etc/foo/my-group: my-username
#   my-app
kubectl delete pod mypod
kubectl apply -f secret-defaultmode-pod.yaml
kubectl exec mypod -- ls -lL /etc/foo
#   -r-------- 1 root root 12 password
#   -r-------- 1 root root  6 username
kubectl delete pod mypod
sed -e 's/key: username/key: nosuchkey/' -e 's/name: mypod$/name: mypod-missing/' secret-items-pod.yaml | kubectl apply -f -
kubectl get pod mypod-missing                       # ContainerCreating (stays there)
kubectl get events --field-selector involvedObject.name=mypod-missing,reason=FailedMount
#   MountVolume.SetUp failed for volume "foo" : references non-existent secret key: nosuchkey
```

### JSON and octal (not from the docs)
```bash
for m in 400 256; do python3 -c "
import yaml,json; d=yaml.safe_load(open('secret-defaultmode-pod.yaml')); d['metadata']['name']='mypod-json-$m'
d['spec']['volumes'][0]['secret']['defaultMode']=$m; print(json.dumps(d))" | kubectl apply -f -; done
kubectl exec mypod-json-400 -- ls -lL /etc/foo/username     # -rw--w----   <- 400 decimal = 0620
kubectl exec mypod-json-256 -- ls -lL /etc/foo/username     # -r--------   <- 256 decimal = 0400
```

## Lab 3 – Environment variables (docs)
```bash
kubectl create secret generic backend-user --from-literal=backend-username='backend-admin'
kubectl create -f pod-single-secret-env-variable.yaml
kubectl exec env-single-secret -- /bin/sh -c 'echo $SECRET_USERNAME'           # backend-admin
kubectl create secret generic db-user --from-literal=db-username='db-admin'
kubectl create -f pod-multiple-secret-env-variable.yaml
kubectl exec envvars-multiple-secrets -- /bin/sh -c 'env | grep _USERNAME'
#   DB_USERNAME=db-admin
#   BACKEND_USERNAME=backend-admin
kubectl create -f pod-secret-envFrom.yaml        # uses test-secret from Lab 1
kubectl exec envfrom-secret -- /bin/sh -c 'echo "username: $username\npassword: $password\n"'
#   username: my-app
#   password: 39528$vdg7Jb
```
(`-i -t` as in the docs prints `Unable to use a TTY` when run from a script; drop it.)

### Updates: volume vs. env (not from the docs)
```bash
kubectl patch secret test-secret -p '{"stringData":{"username":"my-app-v2"}}'
kubectl exec secret-test-pod -- cat /etc/secret-volume/username     # my-app-v2   (after a few seconds)
kubectl exec envfrom-secret -- printenv username                    # my-app      (until the container restarts)
```

## Lab 4 – prod/test credentials (docs example)
```bash
kubectl create secret generic prod-db-secret --from-literal=username=produser --from-literal=password=Y4nys7f11
kubectl create secret generic test-db-secret --from-literal=username=testuser --from-literal=password=iluvtests
kubectl create -f pod.yaml
kubectl get pods -l 'name in (prod-db-client,test-db-client)' \
  -o custom-columns=NAME:.metadata.name,REASON:.status.containerStatuses[0].state.waiting.reason
#   prod-db-client-pod   InvalidImageName   <- "repository name (library/myClientImage) must be lowercase"
#   test-db-client-pod   InvalidImageName
kubectl create -f pod-fixed.yaml                 # NOT from the docs: busybox instead of myClientImage
kubectl logs prod-db-client-pod-fixed            # produser:Y4nys7f11
kubectl logs test-db-client-pod-fixed            # testuser:iluvtests
```
Same Pod template, different Secret: that is the point of the example.

### The service-account shortcut
```bash
kubectl delete pod prod-db-client-pod
kubectl create -f sa-pod.yaml
#   Error from server (Forbidden): … error looking up service account default/prod-db-client: serviceaccount "prod-db-client" not found
kubectl create serviceaccount prod-db-client
kubectl create -f sa-pod.yaml
kubectl get pod prod-db-client-pod -o json | jq -c '[.spec.volumes[].name]'
#   ["kube-api-access-…"]      <- only the token volume; prod-db-secret is NOT mounted
```
To really tie credentials to a ServiceAccount, use the SA's identity (RBAC, token audiences, workload identity), not the SA's `secrets` list.

## Cleanup
```bash
./cleanup.sh
```
