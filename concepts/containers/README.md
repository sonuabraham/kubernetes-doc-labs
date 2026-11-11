# Containers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/containers/

> Sub-pages: [images](images/), [container-environment](container-environment/), [runtime-class](runtime-class/), [container-lifecycle-hooks](container-lifecycle-hooks/), [cri](cri/).
> Cluster: default **`minikube`**.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Container** | A repeatable, standardized unit: the app plus its dependencies behave the same everywhere. It's decoupled from the host infrastructure. (The word is overloaded, so check what your audience means by it.) |
| **In Kubernetes** | Containers run inside **Pods**. The containers of one Pod are **co-located and co-scheduled**: same node, shared network namespace. |
| **Container image** | A ready-to-run package: code, runtime, libraries and default settings. |
| **Immutable** | Don't change the code of a running container. **Build a new image** and recreate the container from it. Changes made inside a running container are lost when it's recreated. |
| **Container runtime** | The software that runs containers (containerd, CRI-O…), talking to the kubelet over the [CRI](cri/). Use a [RuntimeClass](runtime-class/) to pick a different runtime or different settings per Pod. |

## The demo app
[app/v1/Dockerfile](app/v1/Dockerfile) and [app/v2/Dockerfile](app/v2/Dockerfile) are a tiny app that prints its version. You build both **inside minikube**, so no registry is needed. [00-hello.yaml](00-hello.yaml) is Deployment `hello` with container `app` (`local/hello:v1`, `imagePullPolicy: Never`) plus a `sidecar` (nginx) in the same Pod.

---

## Step 1 – Build the images
```bash
cd concepts/containers
minikube image build -t local/hello:v1 app/v1
minikube image build -t local/hello:v2 app/v2
minikube image ls | grep hello            # docker.io/local/hello:v1, :v2  (stored in the node's containerd)
kubectl apply -f 00-hello.yaml
kubectl rollout status deploy/hello -n containers-demo
kubectl logs deploy/hello -c app -n containers-demo --tail=1     # hello from app v1 on hello-…
```

## Lab 1 – Co-located containers share the network, not the filesystem
```bash
kubectl exec deploy/hello -c app -n containers-demo -- wget -qO- http://localhost:80 | grep -o '<title>.*</title>'
#   <title>Welcome to nginx!</title>        <- "app" reaches "sidecar" on localhost: one network namespace
kubectl exec deploy/hello -c app -n containers-demo -- sh -c 'echo patched-by-hand > /hotfix.txt'
kubectl exec deploy/hello -c sidecar -n containers-demo -- ls /hotfix.txt     # No such file - separate filesystems
kubectl get pod -n containers-demo -l app=hello -o wide                        # 2/2 containers, ONE node
```

## Lab 2 – Containers are immutable: hand-made changes vanish
```bash
kubectl exec deploy/hello -c app -n containers-demo -- cat /hotfix.txt         # patched-by-hand (for now)
kubectl delete pod -n containers-demo -l app=hello
kubectl rollout status deploy/hello -n containers-demo
kubectl exec deploy/hello -c app -n containers-demo -- cat /hotfix.txt         # No such file - a fresh container from the image
```

## Lab 3 – The right way: a new image, a new container
```bash
kubectl set image deploy/hello app=local/hello:v2 -n containers-demo
kubectl rollout status deploy/hello -n containers-demo ; sleep 5
kubectl logs deploy/hello -c app -n containers-demo --tail=1     # hello from app v2 on hello-…
kubectl rollout undo deploy/hello -n containers-demo             # going back = the old image, still unchanged
kubectl get pod -n containers-demo -l app=hello -o jsonpath='{.items[0].status.containerStatuses[*].imageID}{"\n"}'
```
Every version is a separate image with its own digest, so rollouts and rollbacks are exact.

## Lab 4 – Which runtime runs them?
```bash
kubectl get node minikube -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}{"\n"}'     # containerd://2.3.4
kubectl get runtimeclass                    # none by default - every Pod uses the default handler
```
Continue with [cri](cri/) and [runtime-class](runtime-class/).

---

## Cleanup
```bash
./cleanup.sh      # namespace + the two local images
```
