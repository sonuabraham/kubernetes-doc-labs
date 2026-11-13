# Configure a kubelet image credential provider – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubelet-credential-provider/

> This is a real end-to-end setup on a throwaway profile **`cred-lab`**:
> - a **private registry** with basic auth ([01-private-registry.yaml](01-private-registry.yaml)) holding `localhost:5000/private/busybox:1.36`
> - an **exec plugin** written as a shell script ([lab-credential-provider](lab-credential-provider)) that the kubelet calls for credentials, configured by [credential-provider-config.yaml](credential-provider-config.yaml)
> - Pods pull the private image with **no imagePullSecrets**
>
> The docs' ECR example config is saved **verbatim** as [credential-provider-config-ecr.yaml](credential-provider-config-ecr.yaml) (reference only: it needs AWS). The service-account-token mode is tested too ([credential-provider-config-sa-token.yaml](credential-provider-config-sa-token.yaml)). Node commands use [../kubeadm/node.sh](../kubeadm/node.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Exec plugin** | A binary on every node. The kubelet runs it with a `CredentialProviderRequest` (JSON) on **stdin** and reads a `CredentialProviderResponse` (same `apiVersion`) on **stdout**. |
| **Kubelet flags** | `--image-credential-provider-config=<file>` and `--image-credential-provider-bin-dir=<dir>`. The provider `name` must equal the binary's filename in that dir. |
| **matchImages** | Decides which images trigger the plugin: the same number of domain parts, `*` per segment, port must match, path is a **prefix**. |
| **Caching** | The kubelet caches the response for `cacheDuration` (or `defaultCacheDuration`), keyed per Image / Registry / Global (`cacheKeyType`). |
| **Service account token mode** | `tokenAttributes` makes the kubelet request a **Pod-bound SA token** for an audience and pass it (plus chosen SA annotations) to the plugin. Workload identity replaces node identity. Gate `KubeletServiceAccountTokenForCredentialProviders` (beta, on in 1.37). With `ServiceAccountNodeAudienceRestriction` (beta, on), nodes need RBAC for that audience. |

---

## Step 0 – cluster + private registry
```bash
cd tasks/administer-cluster/kubelet-credential-provider
minikube start -p cred-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context cred-lab"; N(){ P=cred-lab ../kubeadm/node.sh "$1"; }
HT=$(docker run --rm httpd:2.4-alpine htpasswd -Bbn labuser labpass)          # bcrypt htpasswd line
$K create ns cred-demo
$K -n cred-demo create secret generic registry-htpasswd --from-literal=htpasswd="$HT"
$K apply -f 01-private-registry.yaml
$K -n cred-demo wait --for=condition=Complete job/push-private-image --timeout=180s
$K -n cred-demo logs job/push-private-image | tail -1                         # 1.36
minikube ssh -p cred-lab -- 'curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5000/v2/_catalog'   # 401
```

## Lab 1 – Without a plugin
```bash
$K apply -f 02-private-pod.yaml
$K -n cred-demo get po private-app
#   private-app   0/1   ErrImagePull
$K -n cred-demo get events --field-selector involvedObject.name=private-app,reason=Failed -o custom-columns=MSG:.message | head -1
#   Failed to pull image "localhost:5000/private/busybox:1.36": ... pull access denied, repository does not exist or may require authorization ...
```

## Lab 2 – Install the plugin and configure the kubelet
```bash
minikube -p cred-lab cp lab-credential-provider /etc/kubernetes/credential-providers/lab-credential-provider
minikube -p cred-lab cp credential-provider-config.yaml /etc/kubernetes/credential-provider-config.yaml
N 'chmod +x /etc/kubernetes/credential-providers/lab-credential-provider
   F=/etc/systemd/system/kubelet.service.d/10-kubeadm.conf
   sed -i "s|^ExecStart=/.*|& --image-credential-provider-config=/etc/kubernetes/credential-provider-config.yaml --image-credential-provider-bin-dir=/etc/kubernetes/credential-providers|" $F
   systemctl daemon-reload; systemctl restart kubelet'
$K -n cred-demo delete po private-app; $K apply -f 02-private-pod.yaml
$K -n cred-demo wait --for=condition=Ready po/private-app
$K -n cred-demo logs private-app                         # pulled with plugin-provided credentials
$K -n cred-demo get po private-app -o jsonpath='{.spec.imagePullSecrets}'      # (empty)
N 'cat /var/log/lab-credential-provider.log'
#   12:19:20 args=[--example-argument] request={"kind":"CredentialProviderRequest","apiVersion":"credentialprovider.kubelet.k8s.io/v1","image":"localhost:5000/private/busybox"}
#                                                        <- the image without its tag; args from the config
```

## Lab 3 – matchImages and caching
```bash
$K -n cred-demo run public --image=busybox:1.36 --image-pull-policy=Always -- sleep 3600    # docker.io: doesn't match -> plugin not called
$K -n cred-demo delete po private-app; $K apply -f 02-private-pod.yaml                     # re-pull within the 1m cacheDuration
N 'wc -l < /var/log/lab-credential-provider.log'        # unchanged: answered from the kubelet's cache
```

## Lab 4 – Service account token mode
```bash
minikube -p cred-lab cp credential-provider-config-sa-token.yaml /etc/kubernetes/credential-provider-config.yaml
N 'systemctl restart kubelet'
$K apply -f 03-sa-and-pod.yaml                            # SA "puller" (annotated) + Pod private-app-sa
$K -n cred-demo get po private-app-sa                     # ErrImagePull
N 'journalctl -u kubelet --since "-1m" | grep "Failed to provide credentials"'
#   "Failed to provide credentials for image" err="failed to get service account token: failed to fetch token:
#    serviceaccounts \"puller\" is forbidden: system:node:cred-lab is not authorized to request tokens for audience ..."
$K apply -f 04-node-audience-rbac.yaml                    # system:nodes may request-serviceaccounts-token-audience "lab-registry"
$K -n cred-demo delete po private-app-sa; $K apply -f 03-sa-and-pod.yaml
$K -n cred-demo wait --for=condition=Ready po/private-app-sa
N 'tail -1 /var/log/lab-credential-provider.log'
#   request={"kind":"CredentialProviderRequest", ..., "image":"localhost:5000/private/busybox",
#            "serviceAccountToken":"eyJhbGciOi...", "serviceAccountAnnotations":{"lab.example.com/registry-role":"reader"}}
# decoded token claims: aud=["lab-registry"]  sub=system:serviceaccount:cred-demo:puller  pod=private-app-sa  lifetime 3600s
```
A real plugin would exchange that token with the registry's token service (as cloud workload-identity plugins do) instead of returning static credentials.

---

## Useful commands
```bash
journalctl -u kubelet | grep -i "credential"
echo '{"kind":"CredentialProviderRequest","apiVersion":"credentialprovider.kubelet.k8s.io/v1","image":"localhost:5000/private/busybox"}' \
  | /etc/kubernetes/credential-providers/lab-credential-provider      # run the plugin by hand
```

## Cleanup
```bash
minikube delete -p cred-lab
```
