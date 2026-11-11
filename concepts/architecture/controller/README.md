# Controllers – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/controller/

> Cluster: works on any cluster. The commands assume the **`arch-lab`** profile from [../README.md](../README.md). In this lab you **write a controller yourself**: the docs' thermostat, as a CRD plus a bash control loop.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Control loop** | A loop that never ends: observe the **current state**, compare it with the **desired state**, act to move one closer to the other. A thermostat is one. |
| **Controller** | Tracks at least one resource type. Its `spec` is desired state, and the controller makes reality match it. |
| **Control via the API server** | Most built-in controllers don't do the work themselves. They **ask the API server** to create or remove objects, and other components act on them. The Job controller creates Pods, the scheduler places them, the kubelets run them. |
| **Direct control** | Some controllers change things **outside** the cluster (cloud VMs for the node autoscaler, load balancers, DNS) and then **report** the current state back to the API server. |
| **Updates its own object** | Controllers write status back: a Job is marked `Complete`, and a Deployment gets `availableReplicas`. |
| **Never "done"** | The cluster may never be stable. That's fine as long as controllers keep making useful changes. |
| **Design** | Many small controllers, each using one kind as desired state and managing **another** kind (Job → Pods). Controllers can fail, and the system is designed for that. |
| **Who owns what** | Several controllers create Pods. Each one uses **labels**/selectors (and owner references) to look only at its own. |
| **Where they run** | Built-in ones run inside **kube-controller-manager**. Your own can run as Pods or completely outside the cluster. |

## The demo app
| File | What |
|---|---|
| [01-thermostat-crd.yaml](01-thermostat-crd.yaml) | `Thermostat` kind: `spec.desiredTemperature` (desired) and `status.currentTemperature` / `status.heater` (current) |
| [02-living-room.yaml](02-living-room.yaml) | "Make the living room 22°" |
| [thermostat-controller.sh](thermostat-controller.sh) | The control loop, every 3s. It switches a `heater-<name>` **ConfigMap** (control via the API server), writes `/tmp/heater-<name>` (direct control of an "external system"), simulates the room, and patches `.status` |
| [03-job.yaml](03-job.yaml) | Job, for the built-in Job controller |
| [04-deployment-and-bare-pod.yaml](04-deployment-and-bare-pod.yaml), [05-stray-pod.yaml](05-stray-pod.yaml) | Two creators of Pods |

---

## Step 1
```bash
cd concepts/architecture/controller
kubectl apply -f 00-namespace.yaml -f 01-thermostat-crd.yaml
kubectl wait --for=condition=Established crd/thermostats.home.example.com
kubectl apply -f 02-living-room.yaml
kubectl get thermo -n controller-demo          # DESIRED 22, CURRENT <none> - nothing acts on it yet
```

## Lab 1 – Run your own controller (the thermostat)
Terminal 1:
```bash
./thermostat-controller.sh
#   22:27:35  living-room  desired=22  current=16  heater=on
#   22:27:39  living-room  desired=22  current=17  heater=on
#   ...
#   22:27:59  living-room  desired=22  current=22  heater=idle
```
Terminal 2:
```bash
kubectl get thermo -n controller-demo -w        # CURRENT climbs to 22 - status reported back to the API server
kubectl get cm heater-living-room -n controller-demo -o jsonpath='{.data.state} owner={.metadata.ownerReferences[0].kind}{"\n"}'
#   on owner=Thermostat                             <- the resource it MANAGES (a different kind than it WATCHES)
cat /tmp/heater-living-room                         # the "external system" it controls directly
kubectl patch thermostat living-room -n controller-demo --type=merge -p '{"spec":{"desiredTemperature":19}}'
#   terminal 1:  desired=19  current=21  heater=off ... until 19
```
That's the whole controller pattern: **observe → compare → act → report**.

## Lab 2 – Level-based: stop it, change things, start it
Stop the controller (Ctrl-C). Then:
```bash
kubectl patch thermostat living-room -n controller-demo --type=merge -p '{"spec":{"desiredTemperature":25}}'
kubectl apply -f - <<'EOF'
apiVersion: home.example.com/v1
kind: Thermostat
metadata: {name: bedroom, namespace: controller-demo}
spec: {desiredTemperature: 18}
EOF
kubectl get thermo -n controller-demo          # nothing moves - no controller running
./thermostat-controller.sh                     # restart: it reconciles BOTH rooms from the current state
```
The controller doesn't need the events it missed. It compares desired and current state each time, which is why "controllers can fail" is acceptable.

## Lab 3 – A built-in controller: Job (control via the API server)
```bash
kubectl apply -f 03-job.yaml
kubectl wait --for=condition=Complete job/task -n controller-demo --timeout=60s
kubectl get events -n controller-demo --field-selector involvedObject.kind=Job -o custom-columns=SOURCE:.source.component,REASON:.reason,MESSAGE:.message
#   job-controller   SuccessfulCreate   Created pod: task-k46lv
#   job-controller   SuccessfulCreate   Created pod: task-x7f49
#   job-controller   Completed          Job completed       <- it updates the object that configures it
kubectl get events -n controller-demo --field-selector reason=Scheduled -o custom-columns=SOURCE:.source.component,MESSAGE:.message | grep task
#   default-scheduler  Successfully assigned controller-demo/task-… to arch-lab-m02   <- a DIFFERENT component did the placing
kubectl get job task -n controller-demo -o jsonpath='{.status.conditions[*].type}{"\n"}'    # SuccessCriteriaMet Complete
```

## Lab 4 – Controllers only touch "their" objects
```bash
kubectl apply -f 04-deployment-and-bare-pod.yaml ; kubectl rollout status deploy/web -n controller-demo
kubectl get pods -n controller-demo --show-labels       # task-* (Job's) and web-* (ReplicaSet's) - the Job controller ignores web-*
H=$(kubectl get rs -n controller-demo -l app=web -o jsonpath='{.items[0].metadata.labels.pod-template-hash}')
kubectl label --local -f 05-stray-pod.yaml pod-template-hash=$H -o yaml | kubectl apply -f -   # a bare pod that LOOKS like one of web's
sleep 4
kubectl get pods -n controller-demo -l app=web -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind
kubectl get events -n controller-demo --field-selector reason=SuccessfulDelete -o custom-columns=MSG:.message
#   Deleted pod: stray
```
The ReplicaSet controller saw a pod matching its selector with no controller owner. It **adopted** it, now had 3 pods for 2 replicas, and deleted one. Labels decide which objects a controller considers, and owner references record who owns them. Keep selectors unique.

## Lab 5 – Where the built-in controllers live
```bash
kubectl get pod -n kube-system kube-controller-manager-arch-lab -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep -E 'controllers|leader'
#   --controllers=*,bootstrapsigner,tokencleaner    <- all default controllers + two extra
#   --leader-elect=false                            <- one instance; HA setups run several, with leader election (see ../leases)
kubectl logs -n kube-system kube-controller-manager-arch-lab | grep -o -E '(controller|name)="[a-z-]+' | sort -u
#   controller="deployment  controller="garbagecollector  name="replicaset  controller="taint-eviction-controller  ...
```
Dozens of controllers (deployment, replicaset, job, cronjob, endpointslice, namespace, serviceaccount, node-lifecycle, garbage-collector…) run in **one** process. The thermostat ran outside the cluster. Running it in a Pod would just need an image with `kubectl` and `jq`, plus RBAC.

---

## Useful commands
```bash
kubectl get events --field-selector source=job-controller      # what a controller did
kubectl logs -n kube-system kube-controller-manager-<node>
kubectl get <kind> -o jsonpath='{.metadata.generation} {.status.observedGeneration}'   # has the controller caught up?
```
Write a real one: https://github.com/kubernetes/sample-controller, kubebuilder, or the operator SDK (see `../../extend-kubernetes/operator`).

## Cleanup
```bash
./cleanup.sh       # namespace, CRD, /tmp/heater-* files
```
