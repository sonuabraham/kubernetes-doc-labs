# Enforce Pod Security Standards by Configuring the Built-in Admission Controller – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-admission-controller/

> Needs an API server flag (`--admission-control-config-file`), so it runs on a throwaway profile **`psa-lab`**.
> [use-admission-config.sh](use-admission-config.sh) creates the profile if needed, copies a config file into
> `/var/lib/minikube/certs/psa/` (already mounted into the kube-apiserver Pod), and sets the flag.
> **Stop the default `minikube` first** (two clusters exhaust this host's inotify instances).
> Files: [admission-config.yaml](admission-config.yaml) (docs, **verbatim**, with `v{{< skew currentVersion >}}` rendered as `v1.37`).
> Not from the docs: [admission-config-baseline.yaml](admission-config-baseline.yaml), [test-pods.yaml](test-pods.yaml) (same as in
> [../enforce-standards-namespace-labels](../enforce-standards-namespace-labels/)).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`PodSecurityConfiguration.defaults`** | The level and version used **per mode** (enforce / audit / warn) for namespaces **without** that mode's label. The docs' file is the built-in behaviour: everything `privileged`. |
| **Labels still win** | A namespace label overrides only *its own* mode. The other modes keep the cluster default. |
| **`exemptions`** | `usernames` (the *requesting* user), `runtimeClasses`, `namespaces`. Exempt requests skip **all** modes: no enforce, no warning, no audit. |
| **Not hot-reloaded** | The file is read when kube-apiserver starts. |

---

## Step 0 – The docs' configuration
```bash
cd tasks/configure-pod-container/enforce-standards-admission-controller
minikube stop
./use-admission-config.sh admission-config.yaml
#   15:    - --admission-control-config-file=/var/lib/minikube/certs/psa/admission-config.yaml
#   API server ready
K="kubectl --context psa-lab"
mk(){ $K create ns $1; until $K get sa default -n $1 >/dev/null 2>&1; do sleep 1; done; }   # wait for the SA, or Pods race it
mk docs-defaults; $K apply -n docs-defaults -f test-pods.yaml
#   pod/pod-privileged created   pod/pod-baseline created   pod/pod-restricted created     <- all privileged: no checks, no warnings
```

## Lab 1 – Raise the cluster-wide defaults
[admission-config-baseline.yaml](admission-config-baseline.yaml): enforce **baseline**, warn/audit **restricted** (v1.37), plus one exemption of each kind.
```bash
./use-admission-config.sh admission-config-baseline.yaml          # the kubelet restarts kube-apiserver
mk plain3; $K apply -n plain3 -f test-pods.yaml
```
```
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (…), unrestricted capabilities (…), …
pod/pod-baseline created
pod/pod-restricted created
Error from server (Forbidden): … pods "pod-privileged" is forbidden: violates PodSecurity "baseline:v1.37": host namespaces (hostNetwork=true)
```
This is the same result as the namespace-label lab, but for **every unlabeled namespace** at once.

## Lab 2 – A label overrides only its own mode
```bash
mk labelled; $K label ns labelled pod-security.kubernetes.io/enforce=privileged
$K apply -n labelled -f test-pods.yaml
#   Warning: would violate PodSecurity "restricted:v1.37": host namespaces (hostNetwork=true), …    <- warn = cluster default
#   pod/pod-privileged created                                                                   <- enforce = the label
```

## Lab 3 – The three exemptions
```bash
$K run -n kube-system hostnet-test --image=busybox:1.36 --overrides='{"spec":{"hostNetwork":true}}' -- sleep 3600
#   pod/hostnet-test created              <- namespace exemption (no warning either)
$K run -n plain3 as-admin --image=busybox:1.36 --overrides='{"spec":{"hostNetwork":true}}' \
  --as=lab-admin --as-group=system:masters -- sleep 3600
#   pod/as-admin created                  <- username exemption
$K apply -f - <<'EOF'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: trusted}
handler: runc
EOF
$K run -n plain3 trusted-rc --image=busybox:1.36 --overrides='{"spec":{"hostNetwork":true,"runtimeClassName":"trusted"}}' -- sleep 3600
#   pod/trusted-rc created                <- RuntimeClass exemption (handler runc = no extra isolation!)
```

## Lab 4 – A username exemption doesn't carry over to controllers
```bash
$K create deployment adm-deploy -n plain3 --image=busybox:1.36 --dry-run=client -o json -- sleep 3600 \
  | jq '.spec.template.spec.hostNetwork=true' | $K apply --as=lab-admin --as-group=system:masters -f -
#   deployment.apps/adm-deploy created
$K get events -n plain3 --field-selector reason=FailedCreate
#   replicaset/adm-deploy-… Error creating: pods "adm-deploy-…" is forbidden: violates PodSecurity "baseline:v1.37": host namespaces …
```
The Pods are created by the ReplicaSet controller (`system:serviceaccount:kube-system:replicaset-controller`), not by `lab-admin`.
Exempting controller service accounts would effectively exempt everyone who can create a Deployment. Prefer namespace
or RuntimeClass exemptions.

## Step 5 – Back to the default cluster
```bash
./cleanup.sh          # minikube delete -p psa-lab
minikube start
```

## Useful commands
```bash
minikube -p psa-lab ssh -- "sudo grep admission-control-config-file /etc/kubernetes/manifests/kube-apiserver.yaml"
minikube -p psa-lab ssh -- "sudo cat /var/lib/minikube/certs/psa/admission-config-baseline.yaml"
```

## Cleanup
```bash
./cleanup.sh
```
