# Validate node setup – Hands-on Lab

Based on: https://kubernetes.io/docs/setup/best-practices/node-conformance/

> The page's node conformance test was run on machine **w1** from
> [../../production-environment/tools/kubeadm](../../production-environment/tools/kubeadm/) (Debian 12, kernel 7.0, containerd 2.x,
> kubelet v1.37.2, Docker 29.7.2 enabled just for this). Result: **the documented test can't validate a current node.**
>
> **Found:**
> - **`registry.k8s.io/node-test:0.2` is from 2016-12-09** (the e2e_node suite of about Kubernetes v1.5). It starts its own etcd/API server
>   and runs 88 `[Conformance]` specs against the node's kubelet. All 88 failed in 0.18 s, before testing anything:
>   `system validation failed: [unsupported kernel release: 7.0.0-38-generic, missing cgroups: cpuset memory, unsupported docker version: 29.7.2]`.
>   Its validator only accepts old kernels, cgroup v1 controllers and old Docker releases. (`CGROUPS_CPUSET: missing`, `CGROUPS_MEMORY:
>   missing` on a cgroup v2 host, which has both.)
> - The prerequisites say "a CRI-compatible container runtime such as containerd or CRI-O", but the test is started with **`docker run`**
>   and validates the **Docker** version. A containerd/CRI-O-only node can't run it as documented.
> - **The FOCUS/SKIP examples are broken shell.** `-e FOCUS=MirrorPod \ # Only run MirrorPod test` puts a comment after a line-continuation
>   backslash: bash passes ` # Only run MirrorPod test` as arguments and ends the command at the newline. The next line then runs alone:
>   `registry.k8s.io/node-test:0.2: No such file or directory`.
> - Step 1 (point the kubelet's kubeconfig at `https://127.0.0.1:6443`) isn't enough on a kubeadm node. A kubeconfig without client
>   credentials makes the kubelet fall back to TLS bootstrap: `unable to load bootstrap kubeconfig: stat /etc/kubernetes/bootstrap-kubelet.conf`.
>   Here a temporary drop-in ran the kubelet with only `--kubeconfig` and `--config`.
> - Caveats check: the test image stayed on the node (400 MB). No dead containers were left, because the page's command uses `--rm`.
>
> For current Kubernetes, node conformance is checked by the node e2e suite of the matching release (or cluster-level conformance
> runs, e.g. Sonobuoy / Hydrophone); kubeadm's own `SystemVerification` preflight is the quick check for the basics (see
> [../../production-environment/tools/kubeadm/install-kubeadm](../../production-environment/tools/kubeadm/install-kubeadm/)).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Node conformance test | containerized node e2e: system verification + functional tests of one node's kubelet/runtime |
| Prerequisites | a container runtime + kubelet, kubelet pointed at the test's own API server (`https://127.0.0.1:6443`) |
| `FOCUS` / `SKIP` | ginkgo regexes (image defaults: `FOCUS=\[Conformance\]`, `SKIP=\[Flaky\]\|\[Serial\]`, `PARALLELISM=8`) |
| Leftovers | the test image (and images of test containers) stay on the node |

## Lab
```bash
M=setup/production-environment/tools/kubeadm/machines.sh
docker image inspect registry.k8s.io/node-test:0.2 --format '{{.Created}}'   # 2016-12-09T23:12:16Z   (schema 2 image, still pullable)
# entrypoint: ginkgo --focus="$FOCUS" --skip="$SKIP" --nodes=$PARALLELISM … /usr/local/bin/e2e_node.test -- --conformance=true …

# on w1: docker on, kubelet → https://127.0.0.1:6443 (insecure-skip-tls-verify, read-only port 10255, swap tolerated)
$M x w1 'systemctl enable --now docker'                 # docker 29.7.2
$M x w1 'systemctl restart kubelet; curl -s localhost:10255/healthz'      # ok   (with the --kubeconfig-only drop-in, see Found)

# the page's command (without -it):
$M x w1 'docker run --rm --privileged --net=host -v /:/rootfs -v /etc/kubernetes/manifests:/etc/kubernetes/manifests \
           -v /root/node-test-log:/var/result registry.k8s.io/node-test:0.2'
#   KERNEL_VERSION: 7.0.0-38-generic   CGROUPS_CPUSET: missing   CGROUPS_MEMORY: missing   DOCKER_VERSION: 29.7.2
#   system validation failed: [unsupported kernel release: 7.0.0-38-generic, missing cgroups: cpuset memory, unsupported docker version: 29.7.2]
#   Ran 88 of 162 Specs in 0.177 seconds – FAIL! -- 0 Passed | 88 Failed | 0 Pending | 74 Skipped
#   (/root/node-test-log: junit_01.xml … junit_08.xml)

# the page's FOCUS example, as written (shell parsing shown with a fake docker):
#   docker args: run … -e FOCUS=MirrorPod  # Only run MirrorPod test
#   registry.k8s.io/node-test:0.2: No such file or directory
```

## Cleanup
```bash
$M x w1 'rm /etc/systemd/system/kubelet.service.d/zz-nodetest.conf; systemctl daemon-reload; docker image prune -af; systemctl disable --now docker.service docker.socket; kubeadm reset -f'
```
