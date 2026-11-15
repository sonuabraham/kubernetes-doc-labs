# Pull an Image from a Private Registry – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/

> The docs use Docker Hub and your own Docker ID. To make the lab self-contained, [setup-registry.sh](setup-registry.sh)
> runs a **password-protected registry** (`registry:2` + htpasswd, user `janedoe`) on the minikube node at
> `localhost:5000`, and pushes a private image `localhost:5000/janedoe/jdoe-private:v1` into it with `docker login`/`push`.
> Docker writes to `./docker-config/`, so your `~/.docker/config.json` isn't touched (gitignored).
> Files: [private-reg-pod.yaml](private-reg-pod.yaml), [myregistrykey.yaml](myregistrykey.yaml) (docs, **verbatim**).
> Not from the docs: [00-registry.yaml](00-registry.yaml), [setup-registry.sh](setup-registry.sh), [cached-no-secret.yaml](cached-no-secret.yaml).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`kubernetes.io/dockerconfigjson` Secret** | Holds a docker `config.json`: `{"auths":{"<registry>":{"auth":"base64(user:password)"}}}`. Only base64-encoded, **not** encrypted. |
| **Two ways to create it** | `kubectl create secret generic … --from-file=.dockerconfigjson=config.json --type=…` (from `docker login`), or `kubectl create secret docker-registry …` (credentials on the command line, so they end up in shell history). |
| **`imagePullSecrets`** | Listed on the Pod, or on its ServiceAccount (see [configure-service-account](../configure-service-account/)). The Secret must be in the **Pod's namespace**. Several Secrets, or several registries per Secret, are allowed; the matching registry entry is used. |
| **Who pulls** | The kubelet passes the credentials to containerd on the node. The API server never contacts the registry. |
| **Cached images** | With `KubeletEnsureSecretPulledImages` (beta, **on** in 1.37), a Pod without valid credentials can't reuse an image that was pulled with a Secret, even with `IfNotPresent`. |

```
host docker ──port-forward──► registry:2 (hostNetwork, 127.0.0.1:5000, htpasswd janedoe)  ◄── containerd on the node
   docker login → ./docker-config/config.json ──► Secret regcred ──► Pod.imagePullSecrets ──► kubelet ──┘
```

---

## Step 0 – A private registry with a private image
```bash
cd tasks/configure-pod-container/pull-image-private-registry
./setup-registry.sh
#   Login Succeeded
#   localhost:5000/janedoe/jdoe-private:v1
cat docker-config/config.json         # the docs' "cat ~/.docker/config.json"
```
```json
{ "auths": { "localhost:5000": { "auth": "amFuZWRvZTp4eHh4eHh4eHh4eA==" } } }
```
If your docker uses a credential store, you would see `"credsStore": "…"` here instead of `auth`. Then use the
command-line method (Lab 4).

## Lab 1 – Without credentials
```bash
sed 's|<your-private-image>|localhost:5000/janedoe/jdoe-private:v1|' private-reg-pod.yaml > my-private-reg-pod.yaml
kubectl apply -f my-private-reg-pod.yaml          # regcred doesn't exist yet
kubectl get pod private-reg                       # ErrImagePull → ImagePullBackOff
kubectl describe pod private-reg | grep -E 'FailedToRetrieve|Failed '
#   Warning  FailedToRetrieveImagePullSecret  Unable to retrieve some image pull secrets (regcred); attempting to pull the image may not succeed.
#   Warning  Failed   … Error: ImagePullBackOff
kubectl delete pod private-reg --now
```

## Lab 2 – Secret from the existing config.json (docs)
```bash
kubectl create secret generic regcred \
    --from-file=.dockerconfigjson=docker-config/config.json \
    --type=kubernetes.io/dockerconfigjson
kubectl get secret regcred --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode
kubectl get secret regcred --output="jsonpath={.data.\.dockerconfigjson}" | base64 --decode | jq -r '.auths[].auth' | base64 --decode
#   janedoe:xxxxxxxxxxx               <- anyone who can read the Secret has the password
kubectl apply -f my-private-reg-pod.yaml
kubectl get pod private-reg            # Running
kubectl logs private-reg               # hello from a private image
```

## Lab 3 – Writing the Secret by hand (docs `myregistrykey`)
```bash
kubectl create namespace awesomeapps
kubectl apply -f myregistrykey.yaml
#   The Secret "myregistrykey" is invalid: data[.dockerconfigjson]: Invalid value: "<secret contents redacted>":
#   invalid character 'R' looking for beginning of value
echo -n UmVhbGx5IHJlYWxseSByZWVlZWVlZWVlZWFhYWFh | base64 -d       # Really really reeeeeeeeeeaaaaa
```
The docs' example value is a placeholder, not a config.json. This is exactly the docs' second error case: the base64
decoded fine, but the result isn't valid JSON. The API server validates the content of this Secret type.

## Lab 4 – Credentials on the command line, with a wrong password
```bash
kubectl create secret docker-registry regcred-wrong --docker-server=localhost:5000 \
  --docker-username=janedoe --docker-password=WRONG --docker-email=jdoe@example.com
kubectl get secret regcred-wrong --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d
#   {"auths":{"localhost:5000":{"username":"janedoe","password":"WRONG","email":"jdoe@example.com","auth":"amFuZWRvZTpXUk9ORw=="}}}
sed -e 's/name: private-reg$/name: private-reg-wrong/' -e 's/name: regcred/name: regcred-wrong/' my-private-reg-pod.yaml \
  | sed 's|image: localhost:5000/janedoe/jdoe-private:v1|&\n    imagePullPolicy: Always|' | kubectl apply -f -
kubectl get events --field-selector involvedObject.name=private-reg-wrong,reason=Failed -o jsonpath='{.items[0].message}'
#   … unexpected status from HEAD request to http://localhost:5000/v2/janedoe/jdoe-private/manifests/v1: 401 Unauthorized
```

## Lab 5 – Can another Pod use the cached private image without credentials? (not from the docs)
The image is now on the node, pulled by `private-reg`.
```bash
kubectl apply -f cached-no-secret.yaml            # imagePullPolicy IfNotPresent, no imagePullSecrets
kubectl get pod cached-no-secret                  # ErrImagePull  <- the kubelet re-checked: 401
sed 's/cached-no-secret$/cached-with-secret/' cached-no-secret.yaml \
  | sed 's/^  containers:/  imagePullSecrets: [{name: regcred}]\n  containers:/' | kubectl apply -f -
kubectl describe pod cached-with-secret | grep Pulled
#   Container image "localhost:5000/janedoe/jdoe-private:v1" already present on machine and can be accessed by the pod
minikube ssh -- "sudo ls /var/lib/kubelet/image_manager/"
#   pulled  pulling          <- the kubelet's records of which credentials pulled which image
```
Before `KubeletEnsureSecretPulledImages` (gate check: `kubectl get --raw /metrics | grep KubeletEnsureSecretPulledImages`
gives `BETA 1`), the first Pod would have started from the cache. The old workaround was the `AlwaysPullImages`
admission plugin.

## Useful commands
```bash
kubectl get secrets --field-selector type=kubernetes.io/dockerconfigjson -A
kubectl get pod <p> -o jsonpath='{.spec.imagePullSecrets}'
kubectl get events --field-selector reason=FailedToRetrieveImagePullSecret
```

## Cleanup
```bash
./cleanup.sh      # Pods, Secrets, both namespaces, the image on node + host, ./docker-config
```
