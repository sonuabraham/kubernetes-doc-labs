# Restrict a Container's Access to Resources with AppArmor – Hands-on Lab

Based on: https://kubernetes.io/docs/tutorials/security/apparmor/

> The page assumes "a cluster with AppArmor support". The default minikube (docker driver) is **not** one: a Pod that asks for a profile is
> rejected with `Cannot enforce AppArmor: AppArmor is not enabled on the host` (see
> [concepts/security/linux-kernel-security-constraints](../../../concepts/security/linux-kernel-security-constraints/)). The host kernel has
> AppArmor (`Y`), but the node container has no securityfs mount and no `apparmor_parser`.
> [setup-apparmor-node.sh](setup-apparmor-node.sh) (NOT from the docs) fixes that on a throwaway profile **`apparmor-lab`**. It mounts
> securityfs, installs the `apparmor` package in the node (parser 3.0.8), and restarts containerd and the kubelet.
> **Stop the default `minikube` first** (inotify limit).
>
> Files: [hello-apparmor.yaml](hello-apparmor.yaml) (docs, **verbatim**). NOT from the docs: [profile-types.yaml](profile-types.yaml) and
> [deny-write-fixed.profile](deny-write-fixed.profile).
>
> **Found:**
> - **Pods confined by the docs' profile can't be stopped.** `kubectl delete pod hello-apparmor` hung in `Terminating` indefinitely. The
>   kernel log shows why:
>   `apparmor="DENIED" operation="signal" class="signal" profile="k8s-apparmor-example-deny-write" comm="runc" requested_mask="receive" signal=kill peer="runc"`.
>   The profile has no `signal` rule, so with kernel signal mediation the container can't receive runc's SIGKILL. (The host here is Ubuntu,
>   whose `runc` AppArmor profile attaches to the runc in the node, hence `peer="runc"`.) Reloading the profile with
>   `signal (receive) peer=runc, signal (receive) peer=unconfined,` ([deny-write-fixed.profile](deny-write-fixed.profile)) applies to running
>   processes at once, and both stuck Pods were gone within seconds. [cleanup.sh](cleanup.sh) does that before deleting.
> - In `kubectl describe pod hello-apparmor-2` the docs show `Annotations: container.apparmor.security.beta.kubernetes.io/hello=localhost/…`.
>   On v1.37 it's `Annotations: <none>`: the field is no longer mirrored into the deprecated annotation. The status is
>   `CreateContainerError`; describe says `Status: Pending`.
> - AppArmor profiles live in the **kernel**, which the minikube node shares with the host. Loading one from the node loads it on the host
>   (unattached, so harmless). cleanup.sh unloads `k8s-apparmor-example-deny-write`. containerd's own `cri-containerd.apparmor.d` stays
>   loaded until reboot.
>
> **Note:** the docs install the profile with `ssh $NODE 'sudo apparmor_parser -q <<EOF …'`. Here `minikube -p apparmor-lab ssh -n $NODE '…'`
> does the same. The heredoc is part of the remote command, so `minikube ssh` not forwarding stdin doesn't matter.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| `securityContext.appArmorProfile` | Pod level = default for all containers; container level overrides it (GA field since v1.30, replaces the annotation) |
| `type: Localhost` + `localhostProfile` | a profile already **loaded on the node**; Kubernetes doesn't distribute profiles |
| `type: RuntimeDefault` | containerd's `cri-containerd.apparmor.d`, also used when nothing is set (on an AppArmor-enabled node) |
| `type: Unconfined` | no AppArmor |
| Missing profile | the Pod is scheduled; the container fails with `apparmor profile not found …` |
| Check | `cat /proc/1/attr/current` in the container → `<profile> (enforce)` |

## Lab
```bash
cd tutorials/security/apparmor
minikube stop
./setup-apparmor-node.sh              # profile apparmor-lab:  features policy profiles / AppArmor parser version 3.0.8

NODES=($( kubectl get node -o jsonpath='{.items[*].status.addresses[?(.type == "Hostname")].address}' ))     # (apparmor-lab)
for NODE in ${NODES[*]}; do minikube -p apparmor-lab ssh -n $NODE 'sudo apparmor_parser -q <<EOF
#include <tunables/global>
profile k8s-apparmor-example-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  # Deny all file writes.
  deny /** w,
}
EOF'
done
minikube -p apparmor-lab ssh -- 'sudo grep k8s-apparmor /sys/kernel/security/apparmor/profiles'
#   k8s-apparmor-example-deny-write (enforce)

kubectl create -f hello-apparmor.yaml                     # pod/hello-apparmor created
kubectl exec hello-apparmor -- cat /proc/1/attr/current   # k8s-apparmor-example-deny-write (enforce)
kubectl exec hello-apparmor -- touch /tmp/test
#   touch: /tmp/test: Permission denied
#   command terminated with exit code 1
kubectl logs hello-apparmor                               # Hello AppArmor!

kubectl create -f /dev/stdin <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: hello-apparmor-2
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-apparmor-example-allow-write
  containers:
  - name: hello
    image: busybox:1.28
    command: [ "sh", "-c", "echo 'Hello AppArmor!' && sleep 1h" ]
EOF
kubectl get pod hello-apparmor-2                          # 0/1   CreateContainerError
kubectl describe pod hello-apparmor-2
#   Annotations:      <none>
#   Status:           Pending
#   Warning  Failed  1s (x3 over 13s)  kubelet  spec.containers{hello}: Error: failed to get container spec opts:
#            failed to generate apparmor spec opts: apparmor profile not found k8s-apparmor-example-allow-write
```

NOT from the docs – profile types and precedence ([profile-types.yaml](profile-types.yaml)): the Pod level says deny-write, two containers override it:
```bash
kubectl apply -f profile-types.yaml
for c in inherits-pod runtime-default unconfined; do kubectl exec apparmor-types -c $c -- cat /proc/1/attr/current; done
#   k8s-apparmor-example-deny-write (enforce)     (touch /tmp/x → Permission denied)
#   cri-containerd.apparmor.d (enforce)           (touch works)
#   runc (unconfined)                             (touch works)
kubectl run plain --image=busybox:1.28 -- sleep 1h; kubectl exec plain -- cat /proc/1/attr/current
#   cri-containerd.apparmor.d (enforce)           <- RuntimeDefault without asking
kubectl run bad --image=busybox:1.28 --dry-run=server --overrides='{"spec":{"securityContext":{"appArmorProfile":{"type":"Localhost"}}}}'
#   The Pod "bad" is invalid: spec.securityContext.appArmorProfile.localhostProfile: Required value: must be set when AppArmor type is Localhost
```

NOT from the docs – the stuck delete:
```bash
kubectl delete pod hello-apparmor apparmor-types --now    # hangs; Pods stay Terminating
minikube -p apparmor-lab ssh -- 'sudo dmesg | grep "operation=\"signal\"" | tail -1'
#   apparmor="DENIED" operation="signal" class="signal" profile="k8s-apparmor-example-deny-write" pid=… comm="runc"
#   requested_mask="receive" denied_mask="receive" signal=kill peer="runc"
minikube -p apparmor-lab cp deny-write-fixed.profile /tmp/deny-write-fixed.profile
minikube -p apparmor-lab ssh -- 'sudo apparmor_parser -r /tmp/deny-write-fixed.profile'      # → the Pods disappear
```

## Cleanup
```bash
./cleanup.sh            # fixed profile → delete Pods → unload the profile from the kernel → minikube delete -p apparmor-lab
minikube start
```
