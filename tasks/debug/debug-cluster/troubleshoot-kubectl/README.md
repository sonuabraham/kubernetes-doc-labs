# Troubleshooting kubectl – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/debug/debug-cluster/troubleshoot-kubectl/

> [make-broken-kubeconfigs.sh](make-broken-kubeconfigs.sh) (not from the docs) writes **broken copies** of your minikube kubeconfig into
> `./broken/` (gitignored), one per problem the page lists, so you can see each error message. Your real `~/.kube/config` is never changed.
> Everything is used via `kubectl --kubeconfig=broken/<x>.yaml`.

## Error message → cause (measured)

| Broken copy | What kubectl says | Page section |
|---|---|---|
| good | `namespace/default` | |
| wrong-port (`:9443`) | `The connection to the server 192.168.58.2:9443 was refused - did you specify the right host or port?` | API server / load balancer |
| wrong-host (`127.0.0.1:8443`) | `The connection to the server 127.0.0.1:8443 was refused …` | kubeconfig |
| unreachable (`10.255.255.1`, a blackhole) | `Unable to connect to the server: net/http: request canceled while waiting for connection (Client.Timeout exceeded …)` | VPN / network: *timeout*, not *refused* |
| wrong-ca (another CA in `certificate-authority-data`) | `Unable to connect to the server: tls: failed to verify certificate: x509: certificate signed by unknown authority` | TLS problems |
| bad-token | `error: You must be logged in to the server (Unauthorized)` | authentication |
| missing-helper (`exec: kubectl-oidc_login`) | `Unable to connect to the server: getting credentials: exec: executable kubectl-oidc_login not found` + `It looks like you are trying to use a client-go credential plugin that is not installed.` | kubectl helpers |
| no kubeconfig at all (`KUBECONFIG=/nonexistent`) | `The connection to the server localhost:8080 was refused …` | check kubeconfig: kubectl falls back to localhost:8080 |
| valid user, no permission | `Error from server (Forbidden): secrets is forbidden: User "system:serviceaccount:default:default" cannot list resource "secrets" …` | authorization |

"Refused" means the host is up but nothing listens on that port. "Timeout" means nothing answers at all (routing, VPN, firewall).
Unauthorized means the server doesn't know who you are. Forbidden means it knows, but you aren't allowed.

---

## Step 0
```bash
cd tasks/debug/debug-cluster/troubleshoot-kubectl
./make-broken-kubeconfigs.sh
#   bad-token.yaml good.yaml missing-helper.yaml other-ca.crt other-ca.key unreachable.yaml wrong-ca.yaml wrong-host.yaml wrong-port.yaml
for f in good wrong-port wrong-host unreachable wrong-ca bad-token missing-helper; do
  printf '%-15s ' $f; kubectl --kubeconfig=broken/$f.yaml --request-timeout=5s get ns default -o name 2>&1 | tail -1; done
kubectl get secrets -n kube-system --as=system:serviceaccount:default:default        # Forbidden
KUBECONFIG=/nonexistent kubectl get ns                                               # localhost:8080 refused
```

## Lab 1 – Verify the kubectl setup (docs) – this machine has the problem
```bash
kubectl version
#   Client Version: v1.35.10
#   Server Version: v1.37.0
#   Warning: version difference between client (1.35) and server (1.37) exceeds the supported minor version skew of +/-1
minikube kubectl -- version          # Client Version: v1.37.0   <- a matching kubectl, downloaded by minikube
```
kubectl supports ±1 minor version. Update the snap (`sudo snap refresh kubectl --channel=1.37/stable`), or alias
`kubectl="minikube kubectl --"` for this cluster.

## Lab 2 – Contexts (docs)
```bash
kubectl config get-contexts
#   CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
#   *         minikube            minikube            minikube            default
#             multinode-cluster   multinode-cluster   multinode-cluster   default
kubectl config use-context minikube
```
Gotcha seen in this repo: `minikube start -p <profile>` switches the current context, and `minikube stop` *removes* the
stopped profile's context. If commands suddenly go to the wrong cluster or say `context … does not exist`, check here first.

## Lab 3 – TLS: certificate dates (docs)
```bash
kubectl config view --minify --flatten -o 'jsonpath={.clusters[0].cluster.certificate-authority-data}' | base64 -d | openssl x509 -noout -dates
#   notBefore=Sep 17 12:36:09 2026 GMT   notAfter=Sep 15 12:36:09 2036 GMT      (minikube CA: 10 years)
kubectl config view --minify --flatten -o 'jsonpath={.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -dates -subject
#   notBefore=Nov  6 08:51:17 2026 GMT   notAfter=Nov  6 08:51:17 2029 GMT
#   subject=O=system:masters, CN=minikube-user
```
Two small changes from the docs' commands. `--flatten` is needed because minikube's kubeconfig points to files
(`certificate-authority: /home/…/ca.crt`) instead of embedding `…-data`. `--minify` makes `[0]` the **current** cluster/user,
which matters when the kubeconfig holds several clusters (here `minikube` and `multinode-cluster`). OpenSSL 3.5.5 is installed
(the page needs ≥ 3.0).

## Lab 4 – See what kubectl actually does (not from the docs)
```bash
kubectl --kubeconfig=broken/wrong-ca.yaml --request-timeout=5s -v=6 get ns default
#   loader.go] Config loaded from file:  broken/wrong-ca.yaml           <- which kubeconfig
#   round_trippers.go] "Response" verb="GET" url="https://192.168.58.2:8443/api/v1/namespaces/default?timeout=5s" status=""   <- no HTTP status: TLS failed
```
`-v=6` shows requests, `-v=8` adds bodies, and `-v=9` prints curl-like commands.

## Useful commands
```bash
kubectl config view --minify              # what the current context really uses
kubectl config current-context
kubectl cluster-info
kubectl auth whoami
kubectl get --raw /readyz
```

## Cleanup
```bash
rm -rf broken/
```
