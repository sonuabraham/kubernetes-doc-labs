# Security – Section Page

Based on: https://kubernetes.io/docs/tutorials/security/

> The section page itself only points to the [security checklist](https://kubernetes.io/docs/concepts/security/security-checklist/) and the
> tutorials below.
>
> | Lab | What it shows |
> |---|---|
> | [cluster-level-pss](cluster-level-pss/) | Pod Security Admission defaults for the whole cluster via `--admission-control-config-file` (kind → minikube stand-in) |
> | [ns-level-pss](ns-level-pss/) | Pod Security Standards for one namespace via labels |
> | [apparmor](apparmor/) | Load an AppArmor profile on the node and confine a container with it |
> | [seccomp](seccomp/) | Restrict a container's syscalls with seccomp profiles |
