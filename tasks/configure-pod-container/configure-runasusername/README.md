# Configure RunAsUserName for Windows pods and containers – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/configure-runasusername/

> minikube has no Windows nodes, so the docs' Pods stay `Pending` and you can't run `echo $env:USERNAME` here.
> What **is** real on this cluster: the API server's validation of `runAsUserName` (every rule on the page,
> tested with server-side dry runs), the pod-vs-container precedence in the stored spec, and the `spec.os` interaction.
> Files: [run-as-username-pod.yaml](run-as-username-pod.yaml), [run-as-username-container.yaml](run-as-username-container.yaml)
> (docs, **verbatim**). Not from the docs: [test-usernames.sh](test-usernames.sh).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **`windowsOptions.runAsUserName`** | Windows counterpart of Linux `runAsUser`, but a **name** (`DOMAIN\USER`, the domain is optional), not a number. |
| **Pod vs container** | Pod-level `securityContext.windowsOptions` applies to all containers and init containers. A container-level value **overrides** it for that container. |
| **Built-in users** | `ContainerUser` (unprivileged) and `ContainerAdministrator` (default for most Windows images), plus `NT AUTHORITY\NETWORK SERVICE` and `NT AUTHORITY\LOCAL SERVICE`. |
| **Validated by the API server** | Bad names are rejected at create time, on any cluster, whether or not it has Windows nodes. |
| **Linux** | With `spec.os.name: linux` the field is **forbidden**. Without `spec.os`, a Linux node just **ignores** it. |

## Expected on a real Windows node
```
kubectl exec -it run-as-username-pod-demo -- powershell        > echo $env:USERNAME   -> ContainerUser
kubectl exec -it run-as-username-container-demo -- powershell  > echo $env:USERNAME   -> ContainerAdministrator  (container wins)
```

---

## Step 0
```bash
cd tasks/configure-pod-container/configure-runasusername
```

## Lab 1 – The docs' Pods
```bash
kubectl apply -f run-as-username-pod.yaml
kubectl get pod run-as-username-pod-demo
#   run-as-username-pod-demo   0/1   Pending
kubectl describe pod run-as-username-pod-demo | tail -1
#   Warning FailedScheduling … 0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector.
kubectl apply -f run-as-username-container.yaml
kubectl get pod run-as-username-container-demo -o json \
  | jq -c '{pod:.spec.securityContext.windowsOptions, ctr:.spec.containers[0].securityContext.windowsOptions}'
#   {"pod":{"runAsUserName":"ContainerUser"},"ctr":{"runAsUserName":"ContainerAdministrator"}}
```
Kubernetes stores both values. The Windows kubelet passes the container value to the runtime when it is set,
and the pod value otherwise.

## Lab 2 – Which usernames are valid? (not from the docs)
```bash
./test-usernames.sh
```
```
ContainerUser                  OK
ContainerAdministrator         OK
NT\ AUTHORITY\\NETWORK\ SERVICE OK
NT\ AUTHORITY\\LOCAL\ SERVICE  OK
CONTOSO\\WebApp1               OK            <- NetBIOS domain
contoso.com\\WebApp1           OK            <- DNS domain
''                             REJECTED  runAsUserName cannot be an empty string
$'bad\001name'                 REJECTED  runAsUserName cannot contain control characters
DOMAIN\\                       REJECTED  runAsUserName's User cannot be empty
A-NETBIOS-NAME-16\\u           OK            <- 17 chars: too long for NetBIOS, but a valid DNS name
.dom\\u                        REJECTED  runAsUserName's Domain doesn't match the NetBios nor the DNS format
my-dom-\\u                     OK            <- invalid DNS (ends with "-"), but a valid NetBIOS name
a\\b\\c                        REJECTED  runAsUserName cannot contain more than one backslash
abcdefghijklmnopqrstu          OK            <- 21 chars!
u…u (104)                      OK
u…u (105)                      REJECTED  runAsUserName's User length must not be longer than 104 characters
...                            REJECTED  runAsUserName's User cannot contain only periods or spaces
\ \ \                          REJECTED  runAsUserName's User cannot contain only periods or spaces
user@corp                      REJECTED  runAsUserName's User cannot contain the following characters: "/\:;|=,+*?<>@[]
us:er                          REJECTED  (same)
us\[er\]                       REJECTED  (same)
```
**Different from the page:** it says `USER` is at most 20 characters, but the 1.37 API server allows **104**.
20 is the old Windows SAM-account limit. A domain longer than 255 characters gets
`runAsUserName's Domain length must be under 256 characters`.

## Lab 3 – `spec.os` and Linux nodes (not from the docs)
```bash
kubectl run rau-test --image=busybox --dry-run=server -o name \
  --overrides='{"spec":{"os":{"name":"linux"},"securityContext":{"windowsOptions":{"runAsUserName":"ContainerUser"}}}}'
#   The Pod "rau-test" is invalid: spec.securityContext.windowsOptions: Forbidden: windows options cannot be set for a linux pod

kubectl run rau-linux --image=busybox --restart=Never \
  --overrides='{"spec":{"securityContext":{"windowsOptions":{"runAsUserName":"ContainerUser"}}}}' -- id
kubectl logs rau-linux
#   uid=0(root) gid=0(root) groups=0(root),10(wheel)     <- no spec.os: the Linux kubelet simply ignores windowsOptions
```
So set `spec.os.name: windows` on Windows Pods. The API server then rejects Linux-only fields such as `runAsUser`,
`seLinuxOptions` and `seccompProfile` on them, and vice versa.

## Useful commands
```bash
kubectl explain pod.spec.securityContext.windowsOptions
kubectl get pod <p> -o jsonpath='{.spec.securityContext.windowsOptions}{"\n"}{.spec.containers[*].securityContext.windowsOptions}'
```

## Cleanup
```bash
./cleanup.sh
```
