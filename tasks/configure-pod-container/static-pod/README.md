# Create static Pods – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/

> Runs on the default **minikube** node (the docs assume CRI-O/Fedora; minikube uses containerd, and the steps are the same).
> minikube's kubelet already has `staticPodPath: /etc/kubernetes/manifests`, where the control-plane Pods live. **Only add or remove
> the lab's own files there.**
> Files: [static-web.yaml](static-web.yaml) (docs heredoc, **verbatim**). Not from the docs: [static-web-url.yaml](static-web-url.yaml)
> (the docs' web-hosted manifest, renamed), [web-hosted.sh](web-hosted.sh), [static-with-configmap.yaml](static-with-configmap.yaml).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Static Pod** | Defined by a file (`staticPodPath`) or URL (`staticPodURL`) and managed **only by that node's kubelet**. There is no scheduler or controller; this is how kubeadm/minikube run the control plane. |
| **Mirror Pod** | A read-only *reflection* in the API: `<name>-<node>`, owned by the Node, annotated `kubernetes.io/config.mirror`. Deleting or editing it changes **nothing** on the node. |
| **Every file counts** | All files not starting with `.` are read, whatever the extension. A `*.backup` copy can silently take over. |
| **No API references** | Static Pods can't use ConfigMaps, Secrets, ServiceAccount tokens and the like. The kubelet refuses the manifest and only says so in its log. |

---

## Step 0
```bash
cd tasks/configure-pod-container/static-pod
minikube ssh -- "sudo grep -nE 'staticPod|fileCheck|httpCheck' /var/lib/kubelet/config.yaml; ls /etc/kubernetes/manifests"
#   28:fileCheckFrequency: 0s     32:httpCheckFrequency: 0s     52:staticPodPath: /etc/kubernetes/manifests
#   etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml
```
`fileCheckFrequency: 0s` means the default (20 s), and the directory is also watched with inotify, so new files are picked up at once.

## Lab 1 – Create one (docs)
```bash
minikube cp static-web.yaml /etc/kubernetes/manifests/static-web.yaml        # = the docs' cat <<EOF on the node
minikube ssh -- sudo crictl ps --name web
#   617de6b2ed23c   c05939e13a616   10 seconds ago   Running   web   0   dc7627b46d6d1   static-web-minikube   default
kubectl get pods -l role=myrole -o wide
#   static-web-minikube   1/1   Running   0   13s   10.244.0.9   minikube      <- <name>-<node>, labels propagated
kubectl get pod static-web-minikube -o json | jq -c '{owner:.metadata.ownerReferences[0].kind, src:.metadata.annotations["kubernetes.io/config.source"]}'
#   {"owner":"Node","src":"file"}
```

## Lab 2 – The mirror Pod is only a reflection (docs + extras)
```bash
kubectl delete pod static-web-minikube
kubectl get pods -l role=myrole              # back immediately (briefly Pending); same container ID on the node
C=$(minikube ssh -- "sudo crictl ps --name web -q" | tr -d '\r')
minikube ssh -- "sudo crictl stop $C; sleep 20; sudo crictl ps --name web"
#   b1fd56c0689dd … Running   web   1 …        <- ATTEMPT 1: the kubelet restarted it
kubectl patch pod static-web-minikube -p '{"spec":{"containers":[{"name":"web","image":"nginx:alpine"}]}}'
#   pod/static-web-minikube patched           <- accepted…
kubectl get pod static-web-minikube -o jsonpath='{.spec.containers[0].image}'                   # nginx:alpine
minikube ssh -- "sudo crictl ps --name web -o json" | jq -r '.containers[].image.userSpecifiedImage'   # nginx
```
**The mirror can lie.** After the patch, the API says `nginx:alpine` but the node still runs `nginx`. Only the
manifest file counts.

## Lab 3 – Add and remove by moving the file (docs)
```bash
minikube ssh -- "sudo mv /etc/kubernetes/manifests/static-web.yaml /tmp; sleep 20; sudo crictl ps --name web -q | wc -l"   # 0
kubectl get pod static-web-minikube          # NotFound - the mirror is gone too
minikube ssh -- "sudo mv /tmp/static-web.yaml /etc/kubernetes/manifests/; sleep 20; sudo crictl ps --name web"
#   c7b1799537fc6 … Running   web   2   1abca4adddfd7 …      <- new Pod sandbox
```

## Lab 4 – The backup-file trap (the docs' caution, reproduced)
```bash
minikube ssh -- "sudo sh -c 'sed \"s/role: myrole/role: myrole\n    copy: backup/\" /etc/kubernetes/manifests/static-web.yaml \
  > /etc/kubernetes/manifests/static-web.yaml.backup'"
sleep 25; kubectl get pods -l role=myrole --show-labels
#   static-web-minikube   1/1   Running   0   11s   copy=backup,role=myrole      <- the .backup won, Pod recreated
minikube ssh -- "sudo journalctl -u kubelet --since -1min | grep static-web"
#   "Deleted mirror pod as it didn't match the static Pod" … "Creating a mirror pod for static pod"
minikube ssh -- "sudo rm /etc/kubernetes/manifests/static-web.yaml.backup"
```

## Lab 5 – Static Pods can't use ConfigMaps (not from the docs)
```bash
kubectl create configmap some-config --from-literal=a=1
minikube cp static-with-configmap.yaml /etc/kubernetes/manifests/static-cm.yaml
kubectl get pods | grep static-cm             # nothing - no mirror Pod, no event
minikube ssh -- "sudo journalctl -u kubelet --since -1min | grep static-cm"
#   "Could not process manifest file" err="static pods may not reference configmaps" path="/etc/kubernetes/manifests/static-cm.yaml"
minikube ssh -- "sudo rm /etc/kubernetes/manifests/static-cm.yaml"
```

## Lab 6 – Web-hosted static Pod (docs, via [web-hosted.sh](web-hosted.sh))
```bash
./web-hosted.sh up
#   active
#   httpCheckFrequency: 20s
#   staticPodPath: /etc/kubernetes/manifests
#   staticPodURL: http://127.0.0.1:8099/static-web-url.yaml     <- served by python3 http.server on the node
kubectl get pods -l role=myrole
#   static-web-url-minikube   1/1   Running                     <- config.source: http
sed 's/    role: myrole/    role: myrole\n    version: v2/' static-web-url.yaml > /tmp/v2.yaml
minikube cp /tmp/v2.yaml /srv/static-pods/static-web-url.yaml
sleep 30; kubectl get pods -l role=myrole --show-labels
#   static-web-url-minikube   1/1   Running   0   5s   role=myrole,version=v2      <- re-fetched and recreated
./web-hosted.sh down             # restores /var/lib/kubelet/config.yaml and restarts the kubelet
kubectl get pods -l role=myrole  # the URL Pod is gone
```
A first version of the script tested its backup file without `sudo`. `/var/lib/kubelet` is root-only, so the check was
always false, and a second `up` overwrote the backup with the modified config. If a `down` ever leaves `staticPodURL`
behind, delete that line and set `httpCheckFrequency: 0s` again.

## Useful commands
```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.metadata.annotations["kubernetes.io/config.mirror"]) | .metadata.namespace+"/"+.metadata.name'
minikube ssh -- sudo crictl ps
minikube ssh -- "sudo journalctl -u kubelet --since -5min | grep -E 'file.go|static'"
```

## Cleanup
```bash
./cleanup.sh       # removes only the lab's manifests from /etc/kubernetes/manifests (+ web-hosted mode if left on)
```
