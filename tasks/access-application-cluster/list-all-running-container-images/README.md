# List All Container Images Running in a Cluster – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/access-application-cluster/list-all-running-container-images/

> Runs on the default **minikube** cluster. The commands are the docs' (**verbatim**). [demo-workloads.yaml](demo-workloads.yaml) (**not from the docs**)
> adds an `app=nginx` Deployment and a Pod with an init container (`busybox:1.36`) and a sidecar (`busybox:1.37`).
>
> **Notes:**
> 1. Only the first command includes `initContainers`. The "by Pod", label, namespace, and go-template variants read only `.spec.containers`,
>    so they **miss init containers and native sidecars** (`busybox:1.37` runs, but isn't listed).
> 2. These commands list what the **spec asks for**, not what is "running": a finished init container still counts. For the image a container
>    really runs, read `status.containerStatuses[].imageID` (a digest).

## Key ideas (read first)

| Expression | Meaning |
|---|---|
| `.items[*]` | every Pod of a **list** (omit for `kubectl get pod <name>`) |
| `.spec['initContainers','containers'][*].image` | union of both arrays |
| `{range …}{end}` | loop for line-by-line output |
| `-l`, `-n` | filter by label / namespace before formatting |
| `-o go-template` | Go templates instead of JSONPath |

---

## Lab 1 – All images, counted (docs)
```bash
cd tasks/access-application-cluster/list-all-running-container-images
kubectl apply -f demo-workloads.yaml
kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec['initContainers', 'containers'][*].image}" |\
tr -s '[[:space:]]' '\n' |\
sort |\
uniq -c
#   1 busybox:1.36
#   1 busybox:1.37
#   1 docker.io/kindest/kindnetd:v20260820-69b56db7
#   3 nginx:1.27
#   1 registry.k8s.io/coredns/coredns:v1.14.6
#   1 registry.k8s.io/kube-apiserver:v1.37.0
#   … (etcd, controller-manager, scheduler, proxy, metrics-server@sha256…, csi-hostpath addon images, storage-provisioner)
```

## Lab 2 – By Pod, by label, by namespace, go-template (docs)
```bash
kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' |\
sort
#   coredns-559f6c778d-fsjkx:   registry.k8s.io/coredns/coredns:v1.14.6,
#   nginx-67dc647948-hmlb9:     nginx:1.27,
#   with-init:                  nginx:1.27,          <- no busybox: init/sidecar containers not included
kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}" -l app=nginx
#   nginx:1.27 nginx:1.27
kubectl get pods --namespace kube-system -o jsonpath="{.items[*].spec.containers[*].image}"
#   registry.k8s.io/coredns/coredns:v1.14.6 … gcr.io/k8s-minikube/storage-provisioner:v5
kubectl get pods --all-namespaces -o go-template --template="{{range .items}}{{range .spec.containers}}{{.image}} {{end}}{{end}}"
```

## Lab 3 – Single Pod and what really runs (docs note + extras)
```bash
kubectl get pod with-init -o jsonpath="{.spec['initContainers', 'containers'][*].image}"    # busybox:1.36 busybox:1.37 nginx:1.27
kubectl get pod with-init -o jsonpath="{.items[*].spec.containers[*].image}"                # (empty: no .items on one object)
kubectl get pod with-init -o jsonpath='{range .status.initContainerStatuses[*]}{.name} {.image} {.state}{"\n"}{end}{range .status.containerStatuses[*]}{.name} {.imageID}{"\n"}{end}'
#   setup        docker.io/library/busybox:1.36  {"terminated":{…"exitCode":0…}}     <- listed above, but not running
#   log-shipper  docker.io/library/busybox:1.37  {"running":{…}}
#   app          docker.io/library/nginx@sha256:6784fb0834aa7dbbe12e3d7471e69c290df3e6ba810dc38b34ae33d3c1c05f7d    <- exact image
```

## Cleanup
```bash
./cleanup.sh
```
