# Apply Pod Security Standards at the Cluster Level – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/security/cluster-level-pss/

> The page uses **kind**, which isn't installed here (downloading it was not permitted in this session). So the two kind clusters are
> replaced by two throwaway **minikube** profiles with the same names (`psa-wo-cluster-pss`, `psa-with-cluster-pss`), started by
> [minikube-instead-of-kind.sh](minikube-instead-of-kind.sh) (NOT from the docs). Kubernetes v1.37.0 in both cases (kind v0.33.0 defaults to
> v1.37.0 too). **Stop the default `minikube` first**: two clusters exhaust this host's inotify instances.
>
> Files, **verbatim** from the docs:
> - [cluster-level-pss.yaml](cluster-level-pss.yaml) – the `AdmissionConfiguration` (docs heredoc `/tmp/pss/cluster-level-pss.yaml`)
> - [cluster-config.yaml](cluster-config.yaml) – the kind cluster config (heredoc `/tmp/pss/cluster-config.yaml`; reference only, kind-specific)
> - [example-baseline-pod.yaml](example-baseline-pod.yaml)
> - [kind-with-cluster-level-baseline-pod-security.sh](kind-with-cluster-level-baseline-pod-security.sh) – the "What's next" all-in-one script
>
> **Found:**
> - **The docs' all-in-one script never deletes its cluster.** Its cleanup was copied from the namespace-level script: under `set -e` it runs
>   `kubectl delete pod --all -n example --now` (`No resources found`, rc 0) and then `kubectl delete ns example` →
>   `Error from server (NotFound): namespaces "example" not found` → the script exits 1 **before** `kind delete cluster`. The `nginx` Pod
>   in `default` is never deleted either. Reproduced the two kubectl lines with `set -e` on the lab cluster. Afterwards run
>   `kind delete cluster --name psa-with-cluster-pss` yourself.
> - The dry-run warnings depend on the cluster. On a **brand-new** cluster the DaemonSet Pods (kube-proxy, kindnet) and coredns don't exist
>   yet, so they're missing from the list. Wait until `kube-system` is Ready. On v1.37 minikube the static Pods add `hostPort` and
>   `probe or lifecycle host`, and coredns only fails `runAsNonRoot != true, seccompProfile` for restricted (no `unrestricted capabilities`).
>   minikube has no `local-path-storage` namespace (that's kind's provisioner); its `storage-provisioner` Pod lives in `kube-system`.
> - `audit: restricted` adds audit annotations, but minikube has no audit log configured by default, so only `warn` and `enforce` are
>   visible here.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Pod Security Admission | built-in admission plugin; checks Pods against the `privileged` / `baseline` / `restricted` standards |
| Namespace labels vs cluster defaults | labels set the level per namespace; the `AdmissionConfiguration` sets **defaults** for every namespace without a label |
| Modes | `enforce` rejects, `warn` returns a warning to the client, `audit` annotates the audit event |
| This config | enforce `baseline`, warn + audit `restricted`, `kube-system` exempt |
| `--dry-run=server` + label | preview which existing Pods would violate a level, without changing anything |
| Flag | `kube-apiserver --admission-control-config-file=…`, read only at API server start ("new clusters only") |

## Lab 1 – Choose the right standard (cluster without config)
```bash
cd tutorials/security/cluster-level-pss
minikube stop
./minikube-instead-of-kind.sh wo          # ~ kind create cluster --name psa-wo-cluster-pss
kubectl cluster-info --context psa-wo-cluster-pss     # (kind: --context kind-psa-wo-cluster-pss)
#   Kubernetes control plane is running at https://192.168.193.2:8443
kubectl get ns                            # default, kube-node-lease, kube-public, kube-system
kubectl -n kube-system wait --for=condition=Ready pod --all     # NOT from the docs, see "Found"

kubectl label --dry-run=server --overwrite ns --all pod-security.kubernetes.io/enforce=privileged
#   namespace/default labeled (server dry run)   … no warnings
kubectl label --dry-run=server --overwrite ns --all pod-security.kubernetes.io/enforce=baseline
#   Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "baseline:latest"
#   Warning: etcd-psa-wo-cluster-pss (and 3 other pods): host namespaces, hostPath volumes, hostPort, probe or lifecycle host
#   Warning: kindnet-mn9tg: non-default capabilities, host namespaces, hostPath volumes
#   Warning: kube-proxy-nb4bk: host namespaces, hostPath volumes, privileged
#   Warning: storage-provisioner: host namespaces, hostPath volumes
kubectl label --dry-run=server --overwrite ns --all pod-security.kubernetes.io/enforce=restricted
#   Warning: coredns-559f6c778d-rsvqt: runAsNonRoot != true, seccompProfile
#   Warning: etcd-psa-wo-cluster-pss (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, …
#   Warning: kindnet-mn9tg (and 1 other pod): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, …
#   Warning: kube-proxy-nb4bk: host namespaces, privileged, allowPrivilegeEscalation != false, …
minikube delete -p psa-wo-cluster-pss     # (docs delete it at the very end; one lab cluster at a time here)
```

## Lab 2 – Cluster with the admission configuration
```bash
./minikube-instead-of-kind.sh with        # ~ kind create cluster --name psa-with-cluster-pss --config /tmp/pss/cluster-config.yaml
#   "--admission-control-config-file=/var/lib/minikube/certs/psa/cluster-level-pss.yaml"
kubectl cluster-info --context psa-with-cluster-pss
kubectl apply -f example-baseline-pod.yaml
#   Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" must set
#   securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (…drop=["ALL"]), runAsNonRoot != true (…),
#   seccompProfile (…"RuntimeDefault" or "Localhost")
#   pod/nginx created                     <- baseline is fine, restricted only warns
```
NOT from the docs: the defaults apply to namespaces **without** labels, and `kube-system` is exempt:
```bash
kubectl get ns default --show-labels      # only kubernetes.io/metadata.name=default  (no pod-security labels)
kubectl run priv --image=nginx --privileged
#   Error from server (Forbidden): pods "priv" is forbidden: violates PodSecurity "baseline:latest": privileged (container "priv" must not set securityContext.privileged=true)
kubectl -n kube-system run priv --image=nginx --privileged --dry-run=server     # pod/priv created (server dry run)   <- exempt
kubectl create ns example
kubectl -n example run priv --image=nginx --privileged --dry-run=server         # Forbidden … baseline:latest      <- new namespaces too
```

## Cleanup
Docs: `kind delete cluster --name psa-with-cluster-pss` and `… --name psa-wo-cluster-pss`. Here:
```bash
./cleanup.sh            # deletes both minikube profiles (and /tmp/pss if you made it)
minikube start          # default cluster + its kubectl context back
```
