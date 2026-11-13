# IP Masquerade Agent User Guide – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/ip-masq-agent/

> This follows the docs on a throwaway profile **`masq-lab`**: the agent is installed from the manifest URL the page uses, and the page's two ConfigMap files are kept **verbatim**, each in a file named `config` as the page requires: [config-only-10/config](config-only-10/config) and [config-masq-link-local/config](config-masq-link-local/config). Rules are inspected with the page's `iptables -t nat -L IP-MASQ-AGENT`.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Masquerade** | SNAT many Pod IPs to the node IP for traffic leaving the cluster, for networks that only accept the VM's address (e.g. GCE egress to the internet). |
| **ip-masq-agent** | A DaemonSet that owns the nat chain `IP-MASQ-AGENT`, jumped to from POSTROUTING for non-local destinations: `RETURN` for "non-masquerade" CIDRs, then `MASQUERADE` for the rest. |
| **Defaults** | Non-masquerade = RFC 1918 (`10/8`, `172.16/12`, `192.168/16`) + link-local `169.254/16`. |
| **ConfigMap** | `kube-system/ip-masq-agent`, key **`config`** (mounted at `/etc/config/ip-masq-agent`): `nonMasqueradeCIDRs`, `masqLinkLocal`, `resyncInterval`. Re-read every resync, with no restart. |
| **`masqLinkLocal: true`** | **Do** masquerade link-local: the `169.254.0.0/16` RETURN rule disappears. The page's "ignore link local" means it stops exempting it. |

---

## Step 0 – install
```bash
cd tasks/administer-cluster/ip-masq-agent
minikube start -p masq-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 && kubectl config use-context minikube
K="kubectl --context masq-lab"
$K apply -f https://raw.githubusercontent.com/kubernetes-sigs/ip-masq-agent/master/ip-masq-agent.yaml
#   daemonset.apps/ip-masq-agent created        (image registry.k8s.io/networking/ip-masq-agent:v2.8.0)
$K label nodes masq-lab node.kubernetes.io/masq-agent-ds-ready=true
$K -n kube-system rollout status ds ip-masq-agent
```
The current manifest has **no** nodeSelector, so the label is optional now. It also has no tolerations: on a fresh node it waits until the node is `Ready` (the `not-ready` taint).

## Lab 1 – The default rules
```bash
minikube ssh -p masq-lab -- 'sudo iptables -t nat -L IP-MASQ-AGENT'
#   Chain IP-MASQ-AGENT (1 references)
#   RETURN     all  --  anywhere   link-local/16    /* ip-masq-agent: local traffic is not subject to MASQUERADE */
#   RETURN     all  --  anywhere   10.0.0.0/8       /* ... */
#   RETURN     all  --  anywhere   172.16.0.0/12    /* ... */
#   RETURN     all  --  anywhere   192.168.0.0/16   /* ... */
#   MASQUERADE all  --  anywhere   anywhere         /* ip-masq-agent: outbound traffic is subject to MASQUERADE (must be last in chain) */
minikube ssh -p masq-lab -- 'sudo iptables -t nat -S POSTROUTING'
#   -A POSTROUTING ... -j KUBE-POSTROUTING
#   -A POSTROUTING -m addrtype ! --dst-type LOCAL -m comment --comment "kind-masq-agent: ..." -j KIND-MASQ-AGENT   <- minikube's CNI (kindnet)
#   -A POSTROUTING -m comment --comment "ip-masq-agent: ..." -m addrtype ! --dst-type LOCAL -j IP-MASQ-AGENT      <- ours, AFTER it
```

## Lab 2 – Which chain actually masquerades here?
```bash
minikube ssh -p masq-lab -- 'sudo iptables -t nat -Z KIND-MASQ-AGENT; sudo iptables -t nat -Z IP-MASQ-AGENT'
$K run egress --image=busybox:1.36 --restart=Never -- sh -c 'for i in 1 2 3; do wget -q -T 3 -O /dev/null http://example.com; done'
minikube ssh -p masq-lab -- 'sudo iptables -t nat -L KIND-MASQ-AGENT -v -n | tail -2; sudo iptables -t nat -L IP-MASQ-AGENT -v -n | tail -1'
#      9   540 MASQUERADE  ... /* kind-masq-agent: outbound traffic is subject to MASQUERADE ... */
#      0     0 MASQUERADE  ... /* ip-masq-agent: outbound traffic is subject to MASQUERADE ... */
```
kindnet already embeds the same logic in its own chain, and `MASQUERADE` ends the chain walk, so on minikube the agent's rules never see a packet. On clusters whose CNI doesn't masquerade (the GKE case on the page), `IP-MASQ-AGENT` is what does it.

## Lab 3 – Customize with a ConfigMap (the docs' file `config`)
```bash
cd config-only-10
cat config
#   nonMasqueradeCIDRs:
#     - 10.0.0.0/8
#   resyncInterval: 60s
$K create configmap ip-masq-agent --from-file=config --namespace=kube-system
cd ..
# after the resync (~52 s here):
minikube ssh -p masq-lab -- 'sudo iptables -t nat -L IP-MASQ-AGENT'
#   RETURN     all  --  anywhere   link-local/16   /* ... */
#   RETURN     all  --  anywhere   10.0.0.0/8      /* ... */
#   MASQUERADE all  --  anywhere   anywhere        /* ... */        <- exactly the docs' listing
```

## Lab 4 – `masqLinkLocal: true`
```bash
cd config-masq-link-local
$K create configmap ip-masq-agent --from-file=config --namespace=kube-system --dry-run=client -o yaml | $K apply -f -
cd ..
# after the resync (~94 s here):
minikube ssh -p masq-lab -- 'sudo iptables -t nat -L IP-MASQ-AGENT'
#   RETURN     all  --  anywhere   10.0.0.0/8      /* ... */
#   MASQUERADE all  --  anywhere   anywhere        /* ... */        <- link-local no longer exempt: it is masqueraded
```

---

## Useful commands
```bash
iptables -t nat -L IP-MASQ-AGENT -v -n
kubectl -n kube-system get cm ip-masq-agent -o yaml
kubectl -n kube-system logs ds/ip-masq-agent
```

## Cleanup
```bash
minikube delete -p masq-lab
```
