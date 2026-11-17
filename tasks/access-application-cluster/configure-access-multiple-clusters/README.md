# Configure Access to Multiple Clusters – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/

> Works on kubeconfig **files** only. The `development` and `test` clusters are fake (1.2.3.4, 5.6.7.8); only the last step touches minikube.
> Files (docs, **verbatim**): [config-demo.template](config-demo.template) (the skeleton `config-demo`) and [config-demo-2](config-demo-2).
> You work in `config-exercise/` (gitignored), **never** in `~/.kube/config`.
>
> **Found:**
> 1. Typo in the docs: `set-credentials developer … --client-key=fake-key-seefile`, but the sample output shows `fake-key-file`.
> 2. `kubectl config view` prints `password: REDACTED` (the page shows the password). Use `--raw` to see it.
> 3. The page doesn't mention it: `use-context` with a merged `KUBECONFIG` writes `current-context` into the **first** file in the list.

## Key ideas (read first)

| Term | Meaning |
|---|---|
| cluster | server URL + CA (`certificate-authority[-data]` or `insecure-skip-tls-verify`) |
| user | credentials: client cert/key, token, exec plugin (or username/password, which servers no longer accept) |
| context | (cluster, user, namespace) triple; `current-context` picks one |
| `--kubeconfig` | use exactly this file |
| `KUBECONFIG=a:b:c` | merge the files; first file wins for each name / `current-context`; an empty entry is ignored |

---

## Lab 1 – Build `config-demo` (docs)
```bash
cd tasks/access-application-cluster/configure-access-multiple-clusters
mkdir -p config-exercise && cd config-exercise
cp ../config-demo.template config-demo && cp ../config-demo-2 .
kubectl config --kubeconfig=config-demo set-cluster development --server=https://1.2.3.4 --certificate-authority=fake-ca-file
kubectl config --kubeconfig=config-demo set-cluster test --server=https://5.6.7.8 --insecure-skip-tls-verify
kubectl config --kubeconfig=config-demo set-credentials developer --client-certificate=fake-cert-file --client-key=fake-key-seefile
kubectl config --kubeconfig=config-demo set-credentials experimenter --username=exp --password=some-password
kubectl config --kubeconfig=config-demo set-context dev-frontend --cluster=development --namespace=frontend --user=developer
kubectl config --kubeconfig=config-demo set-context dev-storage --cluster=development --namespace=storage --user=developer
kubectl config --kubeconfig=config-demo set-context exp-test --cluster=test --namespace=default --user=experimenter
#   Cluster "development" set. … Context "exp-test" modified.
kubectl config --kubeconfig=config-demo view | grep -E 'client-key|password'
#   client-key: fake-key-seefile     <- the docs' typo
#   password: REDACTED
kubectl config --kubeconfig=config-demo view --raw | grep password      # password: some-password
```

## Lab 2 – Switch contexts (docs)
```bash
kubectl config --kubeconfig=config-demo use-context dev-frontend        # Switched to context "dev-frontend".
kubectl config --kubeconfig=config-demo view --minify                   # only development / dev-frontend / developer
kubectl --kubeconfig=config-demo get pods
#   Error in configuration: * unable to read client-cert …/config-exercise/fake-cert-file …   <- relative paths are relative to the kubeconfig file
kubectl config --kubeconfig=config-demo use-context exp-test
kubectl --kubeconfig=config-demo get pods --request-timeout=3s
#   … Get "https://5.6.7.8/api?timeout=3s": context deadline exceeded   <- fake server
kubectl config --kubeconfig=config-demo use-context dev-storage
kubectl config --kubeconfig=config-demo view --minify -o jsonpath='{.contexts[0].context.namespace}'    # storage
```

## Lab 3 – Merge with KUBECONFIG (docs)
Run this in a subshell so your real shell keeps its settings:
```bash
( export KUBECONFIG_SAVED="$KUBECONFIG"
  export KUBECONFIG="${KUBECONFIG}:config-demo:config-demo-2"          # here: ":config-demo:config-demo-2"
  kubectl config view -o jsonpath='{range .contexts[*]}{.name} {.context.namespace}{"\n"}{end}'
  #   dev-frontend frontend / dev-ramp-up ramp / dev-storage storage / exp-test default
  kubectl config current-context                                        # dev-storage  (from config-demo)
  export KUBECONFIG="${KUBECONFIG}:${HOME}/.kube/config"
  kubectl config get-contexts -o name                                   # … plus minikube (and any others you have)
  kubectl config use-context dev-ramp-up
  grep -l 'current-context: dev-ramp-up' config-demo config-demo-2 ~/.kube/config     # config-demo   <- first file
  export KUBECONFIG="$KUBECONFIG_SAVED" )
```
Note that without `~/.kube/config` in the list, your real clusters are invisible: `KUBECONFIG` replaces the default, it doesn't add to it.

## Lab 4 – Who am I? (docs)
```bash
kubectl auth whoami                       # with your normal kubeconfig (minikube)
#   Username   minikube-user
#   Groups     [system:masters system:authenticated]
#   Extra: authentication.kubernetes.io/credential-id   [X509SHA256=…]
```

## Cleanup
```bash
./cleanup.sh                              # removes config-exercise/
```
