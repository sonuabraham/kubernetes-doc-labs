#!/usr/bin/env bash
# Read-only check of the page's prerequisites for rootless Kubernetes on THIS host (changes nothing).
u=$(id -un); uid=$(id -u)
echo "cgroup v2:            $(stat -fc %T /sys/fs/cgroup)            (want cgroup2fs)"
echo "delegated controllers: $(cat /sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service/cgroup.controllers 2>/dev/null)   (want cpu cpuset io memory pids)"
echo "subuid:               $(grep "^$u:" /etc/subuid || echo MISSING)"
echo "subgid:               $(grep "^$u:" /etc/subgid || echo MISSING)"
for b in newuidmap newgidmap rootlesskit dockerd-rootless-setuptool.sh slirp4netns; do
  printf '%-22s%s\n' "$b:" "$(command -v $b || echo 'not installed')"; done
echo "unprivileged userns:  $(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null)   (want 1)"
echo "apparmor userns restriction: $(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)   (1 = needs an AppArmor profile for rootlesskit)"
echo "user session (linger): $(loginctl show-user "$u" -p Linger 2>/dev/null)"
