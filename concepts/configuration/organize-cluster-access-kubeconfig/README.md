# Organizing Cluster Access Using kubeconfig Files – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/

> The docs' proxy kubeconfig is **verbatim** in [proxy-kubeconfig.yaml](proxy-kubeconfig.yaml). Its context has no cluster or user, so [proxy-kubeconfig-fixed.yaml](proxy-kubeconfig-fixed.yaml) wires it up. Everything else uses kubeconfig files **generated into `./generated/`** (gitignored) from your minikube credentials. **`~/.kube/config` is never modified.**

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **kubeconfig** | Any file with `clusters` (server + CA), `users` (credentials), `contexts` (cluster + user + namespace) and `current-context`. Default `~/.kube/config`. |
| **Selecting files** | `--kubeconfig` → that **one** file, no merge. Else `$KUBECONFIG` (`:`-separated, `;` on Windows) → **merged**. Else `~/.kube/config`. |
| **Merge rule** | The **first file to set a value or map key wins**, including `current-context` and whole named entries (a `red-user` in file 2 is ignored entirely if file 1 has one). |
| **Resolution chain** | context: `--context` → `current-context`. cluster/user: `--cluster`/`--user` → the context's. Cluster info: `--server`, `--certificate-authority`… → file. User info: `--token`, `--client-certificate`… → file. Anything missing → defaults, maybe a **prompt**. |
| **File references** | Paths **inside** a kubeconfig are relative to that file. Paths on the **command line** are relative to the cwd. |
| **proxy-url** | Per-cluster HTTP(S)/SOCKS5 proxy. |
| **Trust** | A kubeconfig can run commands (`exec` credential plugins) and read files. Treat an untrusted one like a shell script. |

## The demo app
| Script | Writes |
|---|---|
| [make-kubeconfigs.sh](make-kubeconfigs.sh) | `generated/a.yaml`: cluster `lab` (minikube), `red-user` (admin client cert, **relative** paths `certs/…`), context `red` (current) · `generated/b.yaml`: a **different** cluster `lab` (bogus server), a **different** `red-user` (bogus token), `blue-user` (ServiceAccount `kc-demo:developer` token, `edit` in kc-demo only), contexts `blue` (current) and `dev` |
| [make-exec-kubeconfig.sh](make-exec-kubeconfig.sh) | `generated/exec.yaml`: a user whose credentials come from **running** `cred-plugin.sh` |

---

## Step 1
```bash
cd concepts/configuration/organize-cluster-access-kubeconfig
./make-kubeconfigs.sh
grep -E 'certificate|client-' generated/a.yaml
#   certificate-authority: certs/ca.crt     <- given as generated/certs/ca.crt from THIS dir; stored relative to the kubeconfig
cd generated
export KUBECONFIG=a.yaml:b.yaml
```

## Lab 1 – Merging: first one wins
```bash
kubectl config get-contexts
#   CURRENT   NAME   CLUSTER   AUTHINFO    NAMESPACE
#             blue   lab       red-user    kube-system
#             dev    lab2      blue-user   kc-demo
#   *         red    lab       red-user    default      <- a.yaml set current-context first
kubectl config view -o jsonpath='{.clusters[?(@.name=="lab")].cluster.server}'     # https://192.168.58.2:8443  (a.yaml's "lab")
kubectl config view -o jsonpath='{.users[?(@.name=="red-user")].user}'             # client cert only - b.yaml's token was discarded
kubectl --context blue get pods -o name | head -1      # works: blue = b.yaml's context, but a.yaml's "lab" + "red-user"!
KUBECONFIG=b.yaml:a.yaml kubectl config current-context    # blue
KUBECONFIG=b.yaml:a.yaml kubectl get ns default
#   Unable to connect to the server: dial tcp: lookup does-not-exist.example ...   <- now b.yaml's "lab" wins
```

## Lab 2 – Contexts, users and flags
```bash
kubectl --context dev auth whoami | grep Username      # system:serviceaccount:kc-demo:developer
kubectl --context dev get pods                         # No resources found in kc-demo namespace.   (context namespace)
kubectl --context dev get pods -n kube-system          # Forbidden - this identity is limited to kc-demo
kubectl --context red --user blue-user auth whoami | grep Username     # developer: --user beats the context's user
kubectl --context red -n kube-system get pods          # -n beats the context's namespace
kubectl --kubeconfig=a.yaml --context dev get pods     # context was not found: --kubeconfig = one file, no merging
kubectl --context red --token=abc get ns               # works here: the client cert still authenticates (no "conflicting techniques" error)
```

## Lab 3 – Relative file references
```bash
cd /tmp
KUBECONFIG=$OLDPWD/a.yaml kubectl get ns default -o name             # works: certs/… resolved next to a.yaml
KUBECONFIG=$OLDPWD/a.yaml kubectl get ns default --client-certificate=certs/admin.crt
#   unable to read client-cert certs/admin.crt ...                   <- a command-line path is relative to the CWD
cd -
```

## Lab 4 – proxy-url (docs)
```bash
kubectl --kubeconfig=../proxy-kubeconfig.yaml get pods
#   The connection to the server localhost:8080 was refused         <- docs context has no cluster → defaults
kubectl --kubeconfig=../proxy-kubeconfig-fixed.yaml --request-timeout=8s get pods
#   Unable to connect to the server: proxyconnect tcp: dial tcp: lookup proxy.example.org ... no such host   <- went to the proxy first
```
Without the dummy token in the fixed file, kubectl stops at **`Please enter Username:`**. That's the last merge rule: missing auth info → prompt.

## Lab 5 – Why only trusted kubeconfigs
```bash
cd .. ; ./make-exec-kubeconfig.sh ; cd generated
kubectl --kubeconfig=exec.yaml auth whoami | grep Username     # system:serviceaccount:kc-demo:developer
cat exec-ran.log
#   11:25:27 plugin ran as sonu in …/generated - it could have done ANYTHING
```
`users[].user.exec.command` runs on **every** kubectl call with your privileges. Cloud CLIs (`aws eks get-token`, `gke-gcloud-auth-plugin`, `kubelogin`) use exactly this. A hostile file could run anything, or point `certificate-authority`/`tokenFile` at your files.

---

## Useful commands
```bash
kubectl config view [--minify] [--flatten]
kubectl config get-contexts ; kubectl config use-context <c> ; kubectl config current-context
kubectl config set-context --current --namespace=<ns>
kubectl config set-cluster|set-credentials|set-context ... --kubeconfig=<file>
KUBECONFIG=~/.kube/config:other.yaml kubectl config view --flatten > merged.yaml
```

## Cleanup
```bash
unset KUBECONFIG
./cleanup.sh       # namespace kc-demo + the generated/ directory (contains a copy of your admin key!)
```
