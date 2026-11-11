# Annotations – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **Annotation** | Arbitrary, **non-identifying** key/value metadata that tools and libraries can read. |
| **vs labels** | Labels **identify and select** objects (`-l`, selectors). Annotations are **never** selected on. They can be large, structured and use any characters. One object can have both. |
| **Keys** | Same syntax as label keys: `[prefix/]name`. The name is ≤ 63 chars with alphanumerics at both ends, and the prefix is a DNS subdomain. Automation must use a prefix. `kubernetes.io/` and `k8s.io/` are reserved. |
| **Values** | **Strings only**, with **no character restrictions**: spaces, JSON, YAML, multi-line text. Base64-encode binary data (for example CBOR). |
| **Size** | All annotations on one object, keys + values, ≤ **256 KiB** (262144 bytes). |
| **Typical uses** | Declarative tool state (`last-applied-configuration`), build/release info (commit, PR, image digest), links to logs and dashboards, tool or debug info, provenance, rollout checkpoints, on-call contacts, and **directives** to implementations (`kubectl.kubernetes.io/default-container`, `kubernetes.io/change-cause`, ingress controller annotations). |

## The demo app
[annotations-demo.yaml](annotations-demo.yaml) is the docs' Pod, **verbatim**, with `imageregistry: "https://hub.docker.com/"`.
[01-annotated-deployment.yaml](01-annotated-deployment.yaml) is a Deployment `web` with one annotation for each use in the docs' list. Its pod has two containers, `sidecar` and `app`.

---

## Step 1
```bash
cd concepts/overview/working-with-objects/annotations
kubectl apply -f 00-namespace.yaml
kubectl apply -f annotations-demo.yaml -n annotations-demo
kubectl apply -f 01-annotated-deployment.yaml
```

## Lab 1 – Read annotations
```bash
kubectl get pod annotations-demo -n annotations-demo -o jsonpath='{.metadata.annotations}' | jq .
#   "imageregistry": "https://hub.docker.com/"
#   "kubectl.kubernetes.io/last-applied-configuration": "{...}"   <- added by kubectl apply = "fields managed by a declarative configuration layer"
kubectl describe pod annotations-demo -n annotations-demo | sed -n '/Annotations/,/Status/p'
```

## Lab 2 – Any string: URLs, JSON, multi-line
```bash
kubectl get deploy web -n annotations-demo -o json | jq '.metadata.annotations | with_entries(select(.key|startswith("example.com")))'
kubectl get deploy web -n annotations-demo -o jsonpath='{.metadata.annotations.example\.com/rollout-config}' | jq -c .
#   {"maxSurge":"25%","checkpoints":[10,50,100]}       <- a tool can store and parse structured data
kubectl annotate pod annotations-demo -n annotations-demo 'description=Hello, world! <any> "chars" & spaces: ok'
```

## Lab 3 – Annotations as directives to tools
`kubectl.kubernetes.io/default-container` on the pod tells kubectl which container to use:
```bash
kubectl logs deploy/web -n annotations-demo --tail=1     # "APP log" - app, not the first container (sidecar)
kubectl exec deploy/web -n annotations-demo -- hostname  # also runs in "app"
```
`kubernetes.io/change-cause` is shown by `rollout history`:
```bash
kubectl set image deploy/web -n annotations-demo app=busybox:1.37
kubectl annotate deploy/web -n annotations-demo kubernetes.io/change-cause="bump app to busybox 1.37" --overwrite
kubectl rollout history deploy/web -n annotations-demo
#   REVISION  CHANGE-CAUSE
#   1         initial release v1
#   2         bump app to busybox 1.37
```

## Lab 4 – Rules
```bash
kubectl apply -f 02-non-string-value.yaml
#   error: unable to decode ...: json: cannot unmarshal bool into Go struct field ObjectMeta.metadata.annotations of type string
#   (quote it: enabled: "true")
kubectl annotate pod annotations-demo -n annotations-demo 'bad key=x'
#   Invalid value: "bad key": name part must consist of alphanumeric characters, '-', '_' or '.' ...
kubectl get pods -n annotations-demo -l imageregistry=https://hub.docker.com/
#   error / no match - you can't SELECT by annotation (and "https://..." isn't even a valid label value)
kubectl get pods -n annotations-demo -o json | jq -r '.items[] | select(.metadata.annotations.imageregistry) | .metadata.name'
#   annotations-demo     <- filter on the client side instead
```

## Lab 5 – The 256 KiB limit
```bash
./big-annotation.sh 200     # configmap/big-annotation (server dry run)
./big-annotation.sh 260     # The ConfigMap "big-annotation" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```
Watch out: client-side `kubectl apply` copies the whole object into `last-applied-configuration`. A large annotation is then stored **twice**, which can push you over the limit. Large manifests are a common reason to use `kubectl apply --server-side` or `kubectl create`.

## Lab 6 – Add, update, remove
```bash
kubectl annotate pod annotations-demo -n annotations-demo owner=team-a
kubectl annotate pod annotations-demo -n annotations-demo owner=team-b               # error: --overwrite is false
kubectl annotate pod annotations-demo -n annotations-demo owner=team-b --overwrite
kubectl annotate pod annotations-demo -n annotations-demo owner-                     # remove
```

---

## Useful commands
```bash
kubectl annotate <kind> <name> k=v [--overwrite]   ;   kubectl annotate <kind> <name> k-
kubectl get <kind> <name> -o jsonpath='{.metadata.annotations}'
kubectl get <kind> <name> -o jsonpath='{.metadata.annotations.example\.com/key}'   # escape dots
```
Reference: [Well-known labels, annotations and taints](https://kubernetes.io/docs/reference/labels-annotations-taints/).

## Cleanup
```bash
./cleanup.sh
```
