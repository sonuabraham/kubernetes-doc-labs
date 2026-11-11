# Kubernetes Network Policies – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/services-networking/network-policies/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Default** | With no policies, every pod can talk to every pod (and the internet). |
| **Isolation** | A pod becomes *isolated* for Ingress (or Egress) once **any** policy selects it with that policyType. After that, only what is explicitly allowed gets through. |
| **Additive** | Policies never deny, they only allow. The allowed set is the union of all policies that select the pod. Order doesn't matter. |
| **Both ends** | A connection A → B needs egress allowed on A **and** ingress allowed on B. |
| `spec.podSelector` | The pods the policy **protects** (`{}` = all pods in the policy's namespace). |
| `from` / `to` | Who may connect: `podSelector`, `namespaceSelector`, `ipBlock`. |
| `ports` | Restrict by protocol and port; `endPort` makes it a range. |
| `policyTypes` | `Ingress`, `Egress`, or both. If you leave it out, Ingress is always set, and Egress is set only if there are egress rules. |
| **AND vs OR** | `namespaceSelector` + `podSelector` in **one** list item = AND. In **separate** items (each with its own `-`) = OR. |
| **Namespace by name** | Use the automatic label `kubernetes.io/metadata.name: <ns>`. |
| **Layer 4 only** | Policies cover TCP, UDP and SCTP. ICMP (ping) behaviour is undefined, so test with `curl`, not `ping`. |

**Important:** NetworkPolicy objects do nothing unless your CNI plugin enforces them. Use Calico, Cilium, etc.

## The demo app

```
namespace np-demo                          namespace other (label team=partner)
 ┌──────────┐    ┌─────────┐    ┌──────┐     ┌──────────┐
 │ frontend │ -> │ backend │ -> │  db  │     │ outsider │
 └──────────┘    └─────────┘    └──────┘     └──────────┘
 app=frontend    app=backend    app=db       app=outsider
 role=client                    role=db      role=client
```

All pods are `nginx` (port 80, has `curl`). `./test.sh` runs curl from each client and prints **ALLOWED/BLOCKED**.

---

## Step 0 – Cluster with a policy-capable CNI

```bash
# minikube (already installed on this machine)
minikube start --cni=calico
kubectl get pods -n kube-system -l k8s-app=calico-node   # wait until Running

# OR kind (v0.24+ kindnet enforces NetworkPolicy; otherwise install Calico)
# kind create cluster
```

## Step 1 – Deploy the app and see the default (everything open)

```bash
cd network-policies
kubectl apply -f 00-demo-app.yaml
kubectl wait --for=condition=Ready pod --all -n np-demo --timeout=120s
kubectl wait --for=condition=Ready pod --all -n other   --timeout=120s
./test.sh
```
Expected: **everything ALLOWED**.

## Lab 1 – Default deny ingress
```bash
kubectl apply -f 01-default-deny-ingress.yaml
./test.sh
```
Expected: **everything BLOCKED**. Every pod in `np-demo` is now isolated for ingress.

## Lab 2 – Allow frontend → backend
```bash
kubectl apply -f 02-allow-frontend-to-backend.yaml
./test.sh
```
Expected: only `frontend -> backend` is ALLOWED.

## Lab 3 – Allow backend → db on a specific port
```bash
kubectl apply -f 03-allow-backend-to-db-port.yaml
./test.sh
```
Expected: `frontend -> backend` and `backend -> db` are ALLOWED. `frontend -> db` stays BLOCKED.
Experiment: change `port: 80` to `5432` in the file, re-apply, and `backend -> db` is BLOCKED. Change it back afterwards.

## Lab 4 – Allow a whole namespace (namespaceSelector)
```bash
kubectl apply -f 04-allow-from-namespace.yaml
./test.sh
kubectl get ns other --show-labels      # note kubernetes.io/metadata.name=other
```
Expected: `other/outsider -> frontend` is ALLOWED. Outsider still can't reach backend or db.

## Lab 5 – AND vs OR (the most common mistake)
Remove the lab 2 policy so only the selector under test controls backend:
```bash
kubectl delete -f 02-allow-frontend-to-backend.yaml

kubectl apply -f 05a-and-selector.yaml     # one list item  -> AND
./test.sh
```
Expected (AND): `outsider -> backend` ALLOWED (role=client **and** ns team=partner). `frontend -> backend` BLOCKED (its namespace has no team=partner label).

```bash
kubectl delete -f 05a-and-selector.yaml
kubectl apply  -f 05b-or-selector.yaml     # two list items -> OR
./test.sh
```
Expected (OR): `outsider -> backend` and `frontend -> backend` are both ALLOWED.

To see how Kubernetes read a policy:
```bash
kubectl describe netpol or-selector -n np-demo
```
Restore the lab 2 setup:
```bash
kubectl delete -f 05b-or-selector.yaml
kubectl apply  -f 02-allow-frontend-to-backend.yaml
```

## Lab 6 – Default deny egress (+ DNS)
```bash
kubectl apply -f 06-default-deny-egress-allow-dns.yaml
./test.sh
```
Expected: every connection **from** an np-demo pod is BLOCKED. Ingress is still allowed for frontend → backend, but frontend's egress is now denied.
`outsider -> frontend` is still ALLOWED, because the `other` namespace has no egress policy and lab 4 still allows the ingress.
To see why the DNS policy is needed, delete only `allow-dns-egress` and try:
```bash
kubectl delete netpol allow-dns-egress -n np-demo
kubectl exec -n np-demo frontend -- curl -m 3 http://backend   # "Could not resolve host"
kubectl apply -f 06-default-deny-egress-allow-dns.yaml
```

## Lab 7 – Re-open the app's flows on the egress side
```bash
kubectl apply -f 07-egress-allow-app-flow.yaml
./test.sh
```
Expected: `frontend -> backend` and `backend -> db` are ALLOWED again. Each flow needs an egress rule on the source and an ingress rule on the destination.

## Lab 8 – ipBlock (external IPs)
```bash
kubectl apply -f 08-egress-ipblock.yaml
./test.sh external
```
Expected: `frontend -> https://1.1.1.1` ALLOWED, `frontend -> https://1.0.0.1` BLOCKED.
Try the `except` experiment described in the file. (You need internet access from the cluster.)

## Lab 9 – Port ranges (endPort)
```bash
kubectl apply -f 09-endport-range.yaml
kubectl describe netpol multi-port-egress -n np-demo
```
Read-only lab: it shows how to allow TCP ports 32000–32768 to 10.0.0.0/24.

## Lab 10 – Allow all
```bash
kubectl apply -f 10-allow-all.yaml
./test.sh
```
Expected: **everything ALLOWED**, even though all the deny policies are still there. Policies are additive, so `- {}` lets everything through.
```bash
kubectl delete -f 10-allow-all.yaml
```

## Lab 11 – Read the full docs example
```bash
kubectl apply -f 11-docs-full-example.yaml
kubectl describe netpol test-network-policy -n np-demo
```
This policy uses ipBlock + except, namespaceSelector and podSelector (OR'd together), plus ports, on both ingress and egress.

---

## Useful commands
```bash
kubectl get netpol -n np-demo                 # list (short name: netpol)
kubectl describe netpol <name> -n np-demo     # how the API interpreted it
kubectl get pods -n np-demo --show-labels     # selectors match labels
kubectl explain networkpolicy.spec.ingress    # field docs
```

## Cleanup
```bash
./cleanup.sh policies    # remove all policies, keep the app (start over from Lab 1)
./cleanup.sh all         # delete np-demo and other namespaces
minikube delete          # remove the cluster
```

## What NetworkPolicy can't do (per the docs)
- Force traffic through a common gateway (use a service mesh or proxy)
- Anything TLS-related
- Node-specific policies (only CIDRs)
- Target Services by name (use pod/namespace labels)
- Cluster-wide default policies (each namespace needs its own)
- Explicit "deny" rules or logging of blocked connections
