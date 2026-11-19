#include <tunables/global>
profile k8s-apparmor-example-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  # Deny all file writes.
  deny /** w,
  # NOT from the docs: let the runtime stop the container. Without this, runc's SIGKILL is denied on kernels with signal mediation
  # (the host's "runc" profile is the peer here; plain hosts use "unconfined").
  signal (receive) peer=runc,
  signal (receive) peer=unconfined,
}
