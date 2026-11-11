# Images – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/containers/images/

> Cluster: the default single-node **`minikube`** profile. Lab 5 runs a **private, password-protected registry inside the cluster** (on the node's `localhost:5000`), so you can practise `imagePullSecrets` without a Docker Hub account.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Image name** | `[registry[:port]/]path[:tag][@digest]`. No registry means Docker Hub (`docker.io/library/…`). No tag means `latest`. A tag matches `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`. With **tag + digest**, only the digest is used. |
| **Tag vs digest** | Tags can move. Digests (`sha256:…`) are content hashes and **immutable**. Pin with a digest so every Pod runs the same code. |
| **imagePullPolicy** | `IfNotPresent` (pull only if missing), `Always` (ask the runtime every time, which is cheap thanks to layer caching), `Never` (local only, otherwise fail). |
| **Defaulting** | Omitted policy: digest → `IfNotPresent`, `:latest` or no tag → `Always`, any other tag → `IfNotPresent`. It's set **once at creation** and doesn't change when the tag changes later. |
| **ImagePullBackOff** | The pull failed. Retries back off up to **300s**. |
| **Serial / parallel pulls** | The kubelet pulls one image at a time by default (`serializeImagePulls: true`). Set it to false plus `maxParallelImagePulls` for parallel pulls. Pulls for **one** Pod are never parallel. |
| **Multi-arch** | An **image index** points to one manifest per platform, and each node pulls its own. |
| **Private registries** | `imagePullSecrets` on the Pod (recommended; same namespace; type `kubernetes.io/dockerconfigjson`), on a **ServiceAccount**, node-level config, a kubelet **credential provider** plugin (the only option for static pods besides pre-pulling), or **pre-pulled** images. |
| **config.json globs** | Kubernetes allows `*.` per subdomain level and path prefixes: `*.my-registry.example/images` matches `sub.my-registry.example/images/x` but not `a.sub.…`. |
| **KubeletEnsureSecretPulledImages** | A private image cached on a node can't be used by a Pod that lacks credentials for it. The kubelet re-verifies (`imagePullCredentialsVerificationPolicy`, default `NeverVerifyPreloadedImages`). **Active on v1.37** (Lab 5). Otherwise `AlwaysPullImages` is the multi-tenant safeguard. |

## The demo app
| File | What |
|---|---|
| [pod.yaml](pod.yaml), [kustomization.yaml](kustomization.yaml) | The docs' `foo` pod in `awesomeapps` with `imagePullSecrets: myregistrykey`, **verbatim** |
| [config-glob.json](config-glob.json), [config-subpath.json](config-subpath.json) | The docs' two `config.json` examples, **verbatim** (reference) |
| [00-private-registry.yaml](00-private-registry.yaml) | `registry:2.8.3` with htpasswd auth (`student` / `s3cret`) on the node's `localhost:5000` |
| [01-push-private-image.yaml](01-push-private-image.yaml) | Job: `crane copy busybox:1.36 → localhost:5000/private/busybox:1.0` |
| [02-serviceaccount-pull-secret.yaml](02-serviceaccount-pull-secret.yaml) | ServiceAccount with `imagePullSecrets` + a pod using it |
| [03-bad-image.yaml](03-bad-image.yaml) | Non-existent tag, for ImagePullBackOff |

---

## Lab 1 – Image names are normalized
```bash
kubectl create namespace images-demo
for img in busybox busybox:1.36 docker.io/library/busybox:1.36 registry.k8s.io/pause:3.10; do
  kubectl run "n$RANDOM" -n images-demo --image=$img --restart=Never -- sleep 600 >/dev/null; done
sleep 15
kubectl get pods -n images-demo -o custom-columns=SPEC:.spec.containers[0].image,RUNNING:.status.containerStatuses[0].image,DIGEST:.status.containerStatuses[0].imageID
#   busybox        docker.io/library/busybox:latest   docker.io/library/busybox@sha256:…
#   busybox:1.36   docker.io/library/busybox:1.36     docker.io/library/busybox@sha256:73aaf090…
minikube ssh -- sudo crictl images | grep -E 'busybox|pause'
kubectl delete pods -n images-demo --all
```
`status.containerStatuses[].imageID` is the **digest** that actually ran. Use it to pin.

## Lab 2 – Default imagePullPolicy (server dry-run)
```bash
for img in busybox busybox:latest busybox:1.36 busybox@sha256:2142d777d166e724ca5a7c382fbd27cda3e7fa5cc8c104c034984b92691c513b; do
  printf '%-90s %s\n' "$img" "$(kubectl run t --image="$img" -n images-demo --dry-run=server -o jsonpath='{.spec.containers[0].imagePullPolicy}')"; done
```
Expected: `Always`, `Always`, `IfNotPresent`, `IfNotPresent`. That's the docs' four defaulting rules.
Set once: create a Deployment with `busybox:1.36`, then `kubectl set image … =busybox:latest`. The policy **stays** `IfNotPresent`.

## Lab 3 – Never and Always
```bash
kubectl run never -n images-demo --image=busybox:1.31 --image-pull-policy=Never --restart=Never -- sleep 600
kubectl get pod never -n images-demo           # ErrImageNeverPull - not on the node, and we said Never
kubectl run always -n images-demo --image=busybox:1.36 --image-pull-policy=Always --restart=Never -- sleep 600
kubectl get events -n images-demo --field-selector involvedObject.name=always,reason=Pulled -o custom-columns=M:.message
#   Successfully pulled image "busybox:1.36" in 1.2s (...)   <- it asked the registry even though the image was cached
```

## Lab 4 – ImagePullBackOff
```bash
kubectl apply -f 03-bad-image.yaml ; sleep 40
kubectl get events -n images-demo --field-selector involvedObject.name=typo -o custom-columns=REASON:.reason,COUNT:.count,MESSAGE:.message
#   Pulling  3   Pulling image "busybox:1.36-does-not-exist"
#   Failed   3   ... code = NotFound ... failed to pull and unpack image "docker.io/library/busybox:1.36-does-not-exist"
#   BackOff  2   Back-off pulling image ...          <- delay doubles each time, up to 300s
```

## Lab 5 – A private registry and imagePullSecrets
```bash
kubectl apply -f 00-private-registry.yaml ; kubectl wait --for=condition=Ready pod/registry -n images-demo --timeout=120s
kubectl apply -f 01-push-private-image.yaml ; kubectl wait --for=condition=Complete job/push-private-image -n images-demo --timeout=180s
kubectl logs job/push-private-image -n images-demo | tail -1          # 1.0   (tag in the private repo)
```
Without credentials:
```bash
kubectl run nosecret -n images-demo --image=localhost:5000/private/busybox:1.0 --restart=Never -- sleep 3600
kubectl get events -n images-demo --field-selector involvedObject.name=nosecret,reason=Failed -o custom-columns=M:.message | head -2
#   ... pull access denied, repository does not exist or may require authorization: authorization failed: no basic auth credentials
```
With a Secret (the docs' `kubectl create secret docker-registry` command):
```bash
kubectl create secret docker-registry lab-registry -n images-demo \
  --docker-server=localhost:5000 --docker-username=student --docker-password=s3cret --docker-email=student@example.com
kubectl get secret lab-registry -n images-demo -o jsonpath='{.type}{"\n"}'          # kubernetes.io/dockerconfigjson
kubectl get secret lab-registry -n images-demo -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .
kubectl run withsecret -n images-demo --image=localhost:5000/private/busybox:1.0 --restart=Never \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"lab-registry"}]}}' -- sleep 3600
kubectl get pod withsecret -n images-demo          # Running
```
**Now the image is cached on the node.** Can a pod *without* the secret use it?
```bash
kubectl delete pod nosecret -n images-demo
kubectl run nosecret2 -n images-demo --image=localhost:5000/private/busybox:1.0 --image-pull-policy=IfNotPresent --restart=Never -- sleep 3600
kubectl run never-nosecret -n images-demo --image=localhost:5000/private/busybox:1.0 --image-pull-policy=Never --restart=Never -- sleep 3600
kubectl get pods -n images-demo nosecret2 never-nosecret
#   nosecret2        ErrImagePull        <- forced to re-pull to prove its credentials, and it has none
#   never-nosecret   ErrImageNeverPull   <- "not present with pull policy of Never" - for THIS pod it doesn't exist
minikube ssh -- sudo ls /var/lib/kubelet/image_manager      # pulled  pulling   <- the kubelet's pull-credential records
```
This is **KubeletEnsureSecretPulledImages**. Before it existed, `nosecret2` would have started from the cache, which is why the docs recommend `AlwaysPullImages` for multi-tenant clusters.

## Lab 6 – imagePullSecrets via a ServiceAccount
```bash
kubectl apply -f 02-serviceaccount-pull-secret.yaml
kubectl get pod via-serviceaccount -n images-demo -o jsonpath='{.status.phase} injected={.spec.imagePullSecrets}{"\n"}'
#   Running injected=[{"name":"lab-registry"}]       <- added by the ServiceAccount admission plugin
```

## Lab 7 – The docs example (pod.yaml + kustomization.yaml)
```bash
kubectl create namespace awesomeapps
kubectl create secret docker-registry myregistrykey -n awesomeapps --docker-server=https://index.docker.io/v1/ \
  --docker-username=janedoe --docker-password=not-a-real-password --docker-email=jane@example.com
kubectl apply -k .                                    # uses kustomization.yaml -> pod.yaml
kubectl get pod foo -n awesomeapps                    # ErrImagePull - janedoe/awesomeapp:v1 isn't a real image; the wiring is what matters
```

## Lab 8 – Kubelet pull settings and multi-arch
```bash
minikube ssh -- "sudo grep -E 'serializeImagePulls|maxParallelImagePulls' /var/lib/kubelet/config.yaml"   # (absent) = serial pulls, the default
curl -sL -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' https://registry.k8s.io/v2/pause/manifests/3.10 \
  | jq -r '.manifests[] | "\(.platform.os)/\(.platform.architecture) \(.digest[0:19])"'
#   linux/amd64  linux/arm  linux/arm64  linux/ppc64le  linux/s390x  windows/amd64 ...   <- one name, one manifest per platform
#   (pause:3.10 is served as a Docker "manifest list", the older name for an image index)
```

---

## Useful commands
```bash
kubectl get pods -o custom-columns=NAME:.metadata.name,IMAGE:.status.containerStatuses[0].image,ID:.status.containerStatuses[0].imageID
kubectl create secret docker-registry <name> --docker-server=… --docker-username=… --docker-password=…
kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"<secret>"}]}'
minikube ssh -- sudo crictl images | pull <image> | rmi <image>
```

## Cleanup
```bash
./cleanup.sh       # deletes images-demo + awesomeapps and removes the private image from the node
```
