# Ephemeral Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Ephemeral container** | A temporary container you add to a **running** Pod for troubleshooting (stable since 1.25). Normal containers can't be added after creation. |
| **No guarantees** | No resource guarantees, never restarted, not for running applications. |
| **Disallowed fields** | `ports`, `livenessProbe`, `readinessProbe`, `startupProbe`, `resources`, … (Pod resources are fixed). |
| **API** | Added through the **`ephemeralcontainers` subresource**, not `pod.spec`, so `kubectl edit` can't add one. Once added it can't be changed or removed. Not supported for static Pods. |
| **Why** | Distroless/minimal images have no shell or tools, so `kubectl exec` is useless. Also crashed containers. |
| **Process namespace** | `kubectl debug --target=<container>` joins that container's process namespace, so you see its processes. |
| **Access control** | `pods/ephemeralcontainers` is **not** in the default `admin`/`edit` ClusterRoles. Admins must grant `patch` (and `update`) explicitly. |

## The demo app
[00-distroless-app.yaml](00-distroless-app.yaml) is namespace `ephemeral-demo` with pod `distroless` (`registry.k8s.io/pause`: no shell, no tools). [01-rbac.yaml](01-rbac.yaml) defines ServiceAccount `developer` (namespace `edit` role) and `debugger` (`edit` + patch/update on `pods/ephemeralcontainers`).

---

## Lab 1 – exec is useless on a distroless image
```bash
cd concepts/workloads/pods/ephemeral-containers
kubectl apply -f 00-distroless-app.yaml -f 01-rbac.yaml
kubectl wait --for=condition=Ready pod/distroless -n ephemeral-demo
kubectl exec distroless -n ephemeral-demo -- sh
#   error: ... failed to exec in container: ... executable file not found      <- no shell in the image
```

## Lab 2 – kubectl debug: add an ephemeral container
```bash
kubectl debug distroless -n ephemeral-demo --image=busybox:1.36 --target=app -c debugger -- sh -c 'ps; sleep 3600'
sleep 6 ; kubectl logs distroless -c debugger -n ephemeral-demo
#   PID   USER     COMMAND
#     1   65535    /pause            <- the APP's process: we share its process namespace (--target=app)
#    13   root     sh -c ps; ...
kubectl get pod distroless -n ephemeral-demo -o jsonpath='spec: {.spec.ephemeralContainers[0].name} target={.spec.ephemeralContainers[0].targetContainerName}{"\n"}status: {.status.ephemeralContainerStatuses[0].state}{"\n"}'
kubectl get pod distroless -n ephemeral-demo -o jsonpath='{.spec.containers[*].name}{"\n"}'      # app - the regular container list is unchanged
```
Interactive form (in a real terminal): `kubectl debug -it distroless -n ephemeral-demo --image=busybox:1.36 --target=app --profile=general`.
`--profile=general` adds `SYS_PTRACE`, which you need to look inside the target's filesystem through `/proc/1/root`. With the deprecated default (`legacy`) you get `ls: /proc/1/root/: Permission denied`.

## Lab 3 – The API rules
```bash
kubectl patch pod distroless -n ephemeral-demo --type=json \
  -p '[{"op":"add","path":"/spec/ephemeralContainers/-","value":{"name":"x","image":"busybox:1.36"}}]'
#   Forbidden: pod updates may not change fields ...       <- not through pod.spec (why `kubectl edit` can't do it)
kubectl patch pod distroless -n ephemeral-demo --subresource ephemeralcontainers --type=json \
  -p '[{"op":"add","path":"/spec/ephemeralContainers/-","value":{"name":"withres","image":"busybox:1.36","resources":{"requests":{"cpu":"100m"}}}}]'
#   spec.ephemeralContainers[1].resources: Forbidden: cannot be set for an Ephemeral Container
kubectl patch pod distroless -n ephemeral-demo --subresource ephemeralcontainers --type=json \
  -p '[{"op":"add","path":"/spec/ephemeralContainers/-","value":{"name":"withport","image":"busybox:1.36","ports":[{"containerPort":80}]}}]'
#   spec.ephemeralContainers[1].ports: Forbidden: cannot be set for an Ephemeral Container
kubectl patch pod distroless -n ephemeral-demo --subresource ephemeralcontainers --type=json -p '[{"op":"remove","path":"/spec/ephemeralContainers/0"}]'
#   Forbidden: existing ephemeral containers "debugger" may not be removed
```

## Lab 4 – Who may debug?
```bash
for u in developer debugger; do printf '%-10s %s\n' $u "$(kubectl auth can-i patch pods --subresource=ephemeralcontainers -n ephemeral-demo --as=system:serviceaccount:ephemeral-demo:$u)"; done
#   developer  no      <- has the built-in "edit" role, still not allowed
#   debugger   yes
kubectl debug distroless -n ephemeral-demo --image=busybox:1.36 -c try2 --as=system:serviceaccount:ephemeral-demo:developer -- sleep 1
#   Forbidden: ... cannot patch resource "pods/ephemeralcontainers" ...
kubectl debug distroless -n ephemeral-demo --image=busybox:1.36 -c try3 --as=system:serviceaccount:ephemeral-demo:debugger -- sleep 1    # works
```
Adding a container to a running Pod is powerful: it gets the Pod's network, volumes and, with `--target`, its processes. That's why it's a separate, explicitly granted permission.

---

## Useful commands
```bash
kubectl debug -it <pod> --image=busybox --target=<container> --profile=general
kubectl debug <pod> -it --copy-to=<pod>-debug --container=<c> -- sh      # debug a COPY of the pod instead
kubectl debug node/<node> -it --image=busybox                             # debug the node
kubectl get pod <pod> -o jsonpath='{.spec.ephemeralContainers}'
```

## Cleanup
```bash
./cleanup.sh
```
