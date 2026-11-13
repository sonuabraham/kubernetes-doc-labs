# Declare Network Policy – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/

> Runs on the default **minikube** cluster in namespace `default`, as in the docs. minikube's CNI (kindnet) enforces NetworkPolicy. For other providers, see [../network-policy-provider](../network-policy-provider/). [nginx-policy.yaml](nginx-policy.yaml) is the docs' policy, **verbatim**.
>
> The docs use an interactive shell (`kubectl run busybox --rm -ti ... -- /bin/sh`, then `wget ...`). Below, each test is a one-shot Pod whose phase (`Succeeded`/`Failed`) and log give the same answer, and the interactive form is shown too.

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Default** | Without policies, every Pod can reach every Pod. |
| **Selecting = isolating** | Once a NetworkPolicy's `podSelector` matches a Pod (here `app: nginx`), that Pod accepts **only** the ingress the policies allow. |
| **The allow rule** | `from: podSelector: {access: "true"}` means only Pods **in the same namespace** with that label. |
| **Labels, not names** | Access depends on the client's labels when the connection is made, not on the Pod's name. |
| **Propagation** | The CNI must learn a new Pod's IP before allowing it. With kindnet this took about 1 s, so a request in the first moment of a brand-new Pod's life is dropped. |

---

## Step 0 – nginx behind a Service
```bash
cd tasks/administer-cluster/declare-network-policy
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80
kubectl get svc,pod -l app=nginx
#   service/nginx   ClusterIP   10.103.144.12   <none>   80/TCP
#   pod/nginx-69b9cdbbdd-vwn55   1/1   Running
t(){ kubectl run $1 --restart=Never --image=busybox ${2:+--labels=$2} -- sh -c "sleep 2; wget --spider --timeout=1 nginx" >/dev/null
     until kubectl get pod $1 -o jsonpath='{.status.phase}' | grep -qE 'Succeeded|Failed'; do sleep 1; done
     echo "$1: $(kubectl get pod $1 -o jsonpath='{.status.phase}')"; kubectl logs $1; kubectl delete pod $1 --now >/dev/null; }
```

## Lab 1 – Access without a policy
```bash
t bb1                      # docs: kubectl run busybox --rm -ti --image=busybox -- /bin/sh ; wget --spider --timeout=1 nginx
#   bb1: Succeeded
#   Connecting to nginx (10.103.144.12:80)
#   remote file exists
```

## Lab 2 – Assign the policy, test without the label
```bash
kubectl apply -f nginx-policy.yaml
#   networkpolicy.networking.k8s.io/access-nginx created
t bb2
#   bb2: Failed
#   Connecting to nginx (10.103.144.12:80)
#   wget: download timed out
```

## Lab 3 – With the access label
```bash
t bb3 access=true          # docs: kubectl run busybox --rm -ti --labels="access=true" --image=busybox -- /bin/sh
#   bb3: Succeeded
#   Connecting to nginx (10.103.144.12:80)
#   remote file exists
```
The `sleep 2` in `t` matters. Without it, the labelled Pod's very first request also times out:
```bash
#   access=true, wget immediately:  Failed     wget: download timed out
#   access=true, sleep 1 first:     Succeeded  remote file exists
#   no label,    sleep 3 first:     Failed     wget: download timed out
```
In an interactive shell, your typing provides that delay.

---

## Useful commands
```bash
kubectl get networkpolicy ; kubectl describe networkpolicy access-nginx
kubectl get pods --show-labels
kubectl label pod <client> access=true --overwrite        # grant access to a running Pod
```

## Cleanup
```bash
./cleanup.sh        # policy, Service, Deployment
```
