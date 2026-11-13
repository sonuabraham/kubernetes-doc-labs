# Troubleshooting CNI plugin-related errors – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/migrating-from-dockershim/troubleshooting-cni-plugin-related-errors/

> The page is about containerd **v1.6.0–1.6.3** paired with old CNI plugins or configs that don't declare a version. Those exact releases are long gone. Both failure modes are reproduced here by **breaking the version in a CNI config** on the throwaway **`rt-lab`** node ([../start-rt-lab.sh](../start-rt-lab.sh)), whose runtime (cri-dockerd) loads `/etc/cni/net.d/1-k8s.conflist` with the same libcni code. The docs' example config is saved verbatim as [10-containerd-net.conflist](10-containerd-net.conflist).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Two versions meet** | The **config** declares `cniVersion`. Every **plugin binary** lists the spec versions it supports (`CNI_COMMAND=VERSION`). They must overlap. |
| **"Incompatible CNI versions"** | The config version is newer than a plugin supports, so Pod sandboxes can't be created. |
| **"Failed to destroy network for sandbox"** | The config has **no** version. libcni then assumes `0.1.0`, which modern plugins reject, so teardown fails and Pods stick in **Terminating** with the netns still attached. |
| **loopback** | containerd ≥1.6 configures `lo` itself with CNI **1.0.0**, so the `loopback` plugin binary must be ≥1.0.0. |
| **Fix** | Drain → stop runtime and kubelet → upgrade plugins (and the runtime) → set a supported `cniVersion` (e.g. `1.0.0`) → restart → uncordon. |

---

## Step 0
```bash
cd tasks/administer-cluster/migrating-from-dockershim
./start-rt-lab.sh                     # if not running
cd troubleshooting-cni-plugin-related-errors
kubectl --context rt-lab create ns cni-demo
```

## Lab 1 – What the plugins support vs what the config says
```bash
../node.sh 'for p in bridge loopback portmap host-local; do echo "$p: $(CNI_COMMAND=VERSION /opt/cni/bin/$p </dev/null)"; done
  grep cniVersion /etc/cni/net.d/1-k8s.conflist; cp /etc/cni/net.d/1-k8s.conflist /root/1-k8s.conflist.bak'
#   bridge: {"cniVersion":"1.1.0","supportedVersions":["0.1.0","0.2.0","0.3.0","0.3.1","0.4.0","1.0.0","1.1.0"]}
#   loopback: {... same ...}            <- loopback is >= 1.0.0, as the page requires
#     "cniVersion": "0.4.0",
```

## Lab 2 – "Incompatible CNI versions": config newer than the plugins
```bash
kubectl --context rt-lab -n cni-demo run p1 --image=nginx           # a Pod started while the config is good
../node.sh 'sed -i "s/\"cniVersion\": \"0.4.0\"/\"cniVersion\": \"9.9.9\"/" /etc/cni/net.d/1-k8s.conflist; systemctl restart cri-docker'
#   (the runtime reads CNI config at start: without the restart, new Pods still got the cached good config)
kubectl --context rt-lab -n cni-demo run p2 --image=nginx
kubectl --context rt-lab get node rt-lab                 # NotReady
kubectl --context rt-lab -n cni-demo describe po p2 | tail -1
#   Warning  NetworkNotReady  kubelet  network is not ready: ... NetworkPluginNotReady message:docker: network plugin is not ready: cni config uninitialized
../node.sh 'journalctl -u cri-docker -n 5 | grep -m1 "Error validating" | grep -oE "\): .*"'
#   ): [plugin bridge does not support config version \"9.9.9\" plugin portmap does not support config version \"9.9.9\" plugin firewall does not support config version \"9.9.9\"]
```
That's the modern wording of the docs' `incompatible CNI versions; config is "1.0.0", plugin supports ["0.1.0" ... "0.4.0"]`.

## Lab 3 – "Failed to destroy network for sandbox": config without a version
```bash
../node.sh 'cp /root/1-k8s.conflist.bak /etc/cni/net.d/1-k8s.conflist; sed -i "/\"cniVersion\"/d" /etc/cni/net.d/1-k8s.conflist; systemctl restart cri-docker'
kubectl --context rt-lab -n cni-demo delete po p1 --wait=false
kubectl --context rt-lab -n cni-demo get po
#   p1   0/1   Terminating         <- stuck
#   p2   0/1   ContainerCreating
kubectl --context rt-lab -n cni-demo describe po p1 | grep FailedKillPod
#   Warning  FailedKillPod  kubelet  error killing pod: failed to "KillPodSandbox" ... networkPlugin cni failed to teardown pod "p1_cni-demo" network: cni config uninitialized
../node.sh 'journalctl -u cri-docker -n 5 | grep -m1 "Error validating" | grep -oE "\): .*"'
#   ): [plugin firewall does not support config version \"0.1.0\"]       <- missing version = 0.1.0
```

## Lab 4 – The fix: declare a supported version
```bash
../node.sh 'cp /root/1-k8s.conflist.bak /etc/cni/net.d/1-k8s.conflist
  sed -i "s/\"cniVersion\": \"0.4.0\"/\"cniVersion\": \"1.0.0\"/" /etc/cni/net.d/1-k8s.conflist; systemctl restart cri-docker'
kubectl --context rt-lab wait --for=condition=Ready node/rt-lab
kubectl --context rt-lab -n cni-demo get po -o wide
#   p2   1/1   Running   10.244.0.6   rt-lab        <- created; and p1's teardown finally succeeded (gone)
```
The docs' example ([10-containerd-net.conflist](10-containerd-net.conflist)) is a dual-stack `bridge` + `portmap` list at `cniVersion: 1.0.0`. For containerd it goes into `/etc/cni/net.d/`. Adapt the `10.88.0.0/16` / `2001:db8:4860::/64` ranges to your addressing plan. (Here it would lose to `1-k8s.conflist`: the runtime uses the lexically first file.)

---

## Useful commands
```bash
CNI_COMMAND=VERSION /opt/cni/bin/<plugin> </dev/null
ls /etc/cni/net.d ; grep cniVersion /etc/cni/net.d/*.conflist
journalctl -u containerd | grep -i cni     # or -u cri-docker
kubectl get node <n> -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}'
```

## Cleanup
```bash
./cleanup.sh       # restores the original config and deletes cni-demo
```
