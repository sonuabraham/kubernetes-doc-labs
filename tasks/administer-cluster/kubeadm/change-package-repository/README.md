# Changing The Kubernetes Package Repository – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/

> Run inside the **`kubeadm-lab`** node (Debian 12, apt) with [../node.sh](../node.sh). The apt source changes stay inside that throwaway node. The yum/zypper variants are the same idea with `baseurl=` in `/etc/yum.repos.d/kubernetes.repo` or `/etc/zypp/repos.d/kubernetes.repo`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **pkgs.k8s.io** | The community-owned package repos (since 2023). The legacy `apt.kubernetes.io` / `yum.kubernetes.io` are **gone**. |
| **One repo per minor** | `https://pkgs.k8s.io/core:/stable:/v1.37/deb/` only contains 1.37.x. To move to the next minor, **edit the URL**, then `apt update`. That's the whole task. |
| **Verifying** | Check the file that defines the repo (`/etc/apt/sources.list.d/kubernetes.list`): a `pkgs.k8s.io/core:/stable:/vX.Y/` URL means you're on the community repos. |
| **Aliases** | `pkgs.k8s.io` and `pkgs.kubernetes.io` both work (redirects). |
| **Keyring** | One signing key for all minor repos (`/etc/apt/keyrings/kubernetes-apt-keyring.gpg`). |

---

## Lab 1 – Is the legacy repo still there?
```bash
for u in pkgs.k8s.io pkgs.kubernetes.io apt.kubernetes.io; do printf '%-20s ' $u; curl -s -o /dev/null -w '%{http_code}\n' https://$u/core:/stable:/v1.37/deb/Release.key; done
#   pkgs.k8s.io          302     <- redirect to the real download location
#   pkgs.kubernetes.io   302
#   apt.kubernetes.io    404     <- legacy: gone
```

## Lab 2 – Add the v1.36 repo, then switch to v1.37
```bash
cd tasks/administer-cluster/kubeadm
./node.sh 'curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update >/dev/null; apt-cache madison kubeadm | head -3'
#   kubeadm | 1.36.6-1.1 | https://pkgs.k8s.io/core:/stable:/v1.36/deb  Packages
#   kubeadm | 1.36.5-1.1 | ...                                   <- nothing newer than 1.36.x is visible
./node.sh 'cat /etc/apt/sources.list.d/kubernetes.list'           # the docs' "verify" step
./node.sh 'sed -i "s|v1.36|v1.37|" /etc/apt/sources.list.d/kubernetes.list; cat /etc/apt/sources.list.d/kubernetes.list
  apt-get update >/dev/null; apt-cache madison kubeadm | head -3'
#   deb [signed-by=...] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /
#   kubeadm | 1.37.2-1.1 | https://pkgs.k8s.io/core:/stable:/v1.37/deb  Packages
#   kubeadm | 1.37.1-1.1 | ...
#   kubeadm | 1.37.0-1.1 | ...
```
The same key worked for both minors (no new `Release.key` needed).

## Lab 3 – Holds and candidates (after `../kubeadm-upgrade` installed 1.37.0)
```bash
./node.sh 'apt-cache policy kubeadm | head -3; apt-mark showhold'
#   kubeadm:
#     Installed: 1.37.0-1.1
#     Candidate: 1.37.2-1.1          <- available, but...
#   kubeadm kubectl kubelet           <- ...held: apt upgrade won't touch them
```

---

## Cleanup
Nothing outside the throwaway node. `minikube stop -p kubeadm-lab` when you're done with the kubeadm labs.
