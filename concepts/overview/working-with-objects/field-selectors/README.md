# Field Selectors – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/field-selectors/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Field selector** | Filters objects by the **value of a resource field**, such as `status.phase=Running`. Filtering happens on the **server**. |
| **Default** | No selector means everything. `--field-selector ""` is the same as not passing one. |
| **Supported fields** | Every type supports `metadata.name` and `metadata.namespace`. Some types add a few more (table below). Anything else is a `BadRequest` error. It is **not** "any field in the YAML". |
| **Operators** | `=`, `==` (same thing) and `!=`. **No** set-based operators (`in`, `notin`, `exists`). |
| **Chaining** | Comma-separated requirements are ANDed: `status.phase!=Running,spec.restartPolicy=Always`. |
| **Multiple types** | `kubectl get statefulsets,services --field-selector …` applies the selector to each type. |
| **Custom resources** | `metadata.name` and `metadata.namespace`, plus any field the CRD lists in `spec.versions[*].selectableFields`. |
| **vs label selectors** | Labels are your own key/values with set-based operators (`-l`). Field selectors work on built-in fields with equality only (`--field-selector`). You can use both together. |

### Supported fields (from the docs)
| Kind | Fields |
|---|---|
| Pod | `spec.nodeName`, `spec.restartPolicy`, `spec.schedulerName`, `spec.serviceAccountName`, `spec.hostNetwork`, `status.phase`, `status.podIP`, `status.podIPs`, `status.nominatedNodeName` |
| Event | `involvedObject.kind/namespace/name/uid/apiVersion/resourceVersion/fieldPath`, `reason`, `reportingComponent`, `source`, `type` |
| Secret | `type` |
| Service | `spec.clusterIP`, `spec.type` |
| Namespace | `status.phase` |
| ReplicaSet / ReplicationController | `status.replicas` (**see Lab 5**: on v1.37 only the ReplicationController accepts it) |
| Job | `status.successful` |
| Node | `spec.unschedulable` |
| CertificateSigningRequest | `spec.signerName` |

## The demo app
[00-demo-app.yaml](00-demo-app.yaml) in namespace `fieldsel-demo` contains one object for each interesting field value:

| Object | Field value |
|---|---|
| pod `running` | `status.phase=Running`, `restartPolicy=Always` |
| pod `crashing` | `status.phase=Running`. CrashLoopBackOff is a container state, **not** a phase |
| pod `pending` | `status.phase=Pending` (its nodeSelector matches no node) |
| pod `done` | `status.phase=Succeeded`, `serviceAccountName=builder` |
| pod `broken` | `status.phase=Failed` |
| pod `on-host-net` | `spec.hostNetwork=true` |
| Services `web`, `web-nodeport`, `db-headless` | ClusterIP / NodePort / `clusterIP: None` |
| Secrets `plain`, `login` | `Opaque` / `kubernetes.io/basic-auth` |
| Job `hello` | `status.successful=1` |
| StatefulSet `db` | for the multi-type example |

[01-crd-selectable-fields.yaml](01-crd-selectable-fields.yaml) and [02-shirts.yaml](02-shirts.yaml) add a CRD `Shirt` with `selectableFields: .spec.color, .spec.size`.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/field-selectors
kubectl apply -f 00-demo-app.yaml -f 01-crd-selectable-fields.yaml
kubectl wait --for=condition=Established crd/shirts.stable.example.com
kubectl apply -f 02-shirts.yaml
kubectl wait --for=condition=Complete job/hello -n fieldsel-demo --timeout=90s ; sleep 15   # let "crashing" crash
```
The helper below prints only the names:
```bash
f(){ printf '%-60s ' "$*"; kubectl get "$@" -o name 2>&1 | sed 's#^[a-z.]*/##' | tr '\n' ' ' | cut -c1-160; echo; }
```

## Lab 1 – The docs examples
```bash
f pods -n fieldsel-demo --field-selector status.phase=Running
f pods -n fieldsel-demo --field-selector ""
f services --all-namespaces --field-selector metadata.namespace!=default
f pods -n fieldsel-demo --field-selector=status.phase!=Running,spec.restartPolicy=Always
f statefulsets,services --all-namespaces --field-selector metadata.namespace!=default
f ingress --field-selector foo.bar=baz
```
Expected:
```
status.phase=Running                       crashing db-0 on-host-net running        <- "crashing" IS Running
""                                         all 8 pods (broken crashing db-0 done hello-xxxxx on-host-net pending running)
services ... metadata.namespace!=default   web web-nodeport db-headless kube-dns ...
status.phase!=Running,restartPolicy=Always pending
statefulsets,services ... !=default        db db-headless web web-nodeport kube-dns ...
ingress foo.bar=baz                        Error from server (BadRequest): ... "foo.bar" is not a known field selector: only "metadata.name", "metadata.namespace"
```

## Lab 2 – Every pod phase
```bash
for p in Pending Running Succeeded Failed; do f pods -n fieldsel-demo --field-selector status.phase=$p; done
```
Expected: `pending` | `crashing db-0 on-host-net running` | `done hello-xxxxx` | `broken`.
A common use is cleaning up finished pods: `kubectl delete pods -n fieldsel-demo --field-selector status.phase=Succeeded`.

## Lab 3 – Other Pod fields
```bash
f pods -n fieldsel-demo --field-selector spec.hostNetwork=true                   # on-host-net
f pods -n fieldsel-demo --field-selector spec.serviceAccountName=builder         # done
f pods -A --field-selector spec.nodeName=minikube,metadata.namespace=fieldsel-demo   # everything scheduled (not "pending")
f pods -n fieldsel-demo --field-selector status.podIP=$(kubectl get pod running -n fieldsel-demo -o jsonpath='{.status.podIP}')   # running
```
`spec.nodeName=<node>` is what the kubelet itself uses to watch only its own pods.

## Lab 4 – Services, Secrets, Jobs, Nodes, Namespaces, Events
```bash
f services -n fieldsel-demo --field-selector spec.type=NodePort                  # web-nodeport
f services -n fieldsel-demo --field-selector spec.clusterIP=None                 # db-headless
f secrets  -n fieldsel-demo --field-selector type=kubernetes.io/basic-auth       # login
f jobs     -n fieldsel-demo --field-selector status.successful=1                 # hello
f nodes --field-selector spec.unschedulable=false                                # minikube (try after: kubectl cordon minikube; then uncordon)
f namespaces --field-selector status.phase=Active,metadata.name=fieldsel-demo    # fieldsel-demo
f events -n fieldsel-demo --field-selector type=Warning                          # crashing.…, pending.…
f events -n fieldsel-demo --field-selector involvedObject.name=crashing,reason=BackOff
```
Events are the most common use in practice: `kubectl get events --field-selector involvedObject.name=<pod>`.

## Lab 5 – What doesn't work
```bash
f pods -n fieldsel-demo --field-selector 'status.phase in (Running,Pending)'    # invalid selector - no set-based operators
f pods -n fieldsel-demo --field-selector metadata.labels.app=db                 # field label not supported (use -l)
f deployments -A --field-selector spec.replicas=1                               # not a known field selector
f replicasets -A --field-selector status.replicas=0
```
The last one is listed in the docs table, but on **v1.37** it fails with `"status.replicas" is not a known field selector: only "metadata.name", "metadata.namespace"`. ReplicationControllers (`kubectl get rc --field-selector status.replicas=0`) still accept it. Always check against your cluster.

## Lab 6 – Custom resources with selectableFields
```bash
kubectl get shirts -n fieldsel-demo                                              # example1 blue S, example2 blue M, example3 green M
f shirts -n fieldsel-demo --field-selector spec.color=blue                       # example1 example2
f shirts -n fieldsel-demo --field-selector spec.color=blue,spec.size=M           # example2
f shirts -n fieldsel-demo --field-selector spec.size!=M                          # example1
f shirts -n fieldsel-demo --field-selector metadata.name=example3                # always available
```
Remove `selectableFields` from the CRD and re-apply. `spec.color` then becomes an unknown field selector.

## Lab 7 – On the wire
```bash
kubectl get --raw "/api/v1/namespaces/fieldsel-demo/pods?fieldSelector=status.phase%3DFailed" | jq -r '.items[].metadata.name'
#   broken
kubectl get pods -n fieldsel-demo --field-selector status.phase=Running -l app=db   # field + label selectors together: db-0
```

---

## Useful commands
```bash
kubectl get events --field-selector involvedObject.name=<name>,type=Warning
kubectl get pods -A --field-selector spec.nodeName=<node>          # what runs on a node
kubectl delete pods --field-selector status.phase=Failed            # clean up failed pods
kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded   # anything unhealthy-ish
```

## Cleanup
```bash
./cleanup.sh          # deletes fieldsel-demo and the Shirt CRD
```
