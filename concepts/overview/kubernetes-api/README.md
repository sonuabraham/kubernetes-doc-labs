# The Kubernetes API – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/overview/kubernetes-api/

> Everything in Kubernetes goes through the **API server's HTTP API**: kubectl, kubeadm, the kubelet, controllers, and your own programs through client libraries. In this lab you skip kubectl and use the API directly with `curl`, through `kubectl proxy`.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **REST API** | Objects are resources at URLs. Core group: `/api/v1/namespaces/<ns>/<resource>/<name>`. Named groups: `/apis/<group>/<version>/...`. HTTP verbs map to operations: GET (get/list/watch), POST (create), PUT (update), PATCH, DELETE. |
| **Discovery API** | A short summary of what the cluster serves: groups, versions, resources, scope, verbs, short names, kind. No schemas. |
| **Unaggregated discovery** | `/api` and `/apis` list group versions, then **one request per group version** (`/apis/apps/v1`) lists its resources. |
| **Aggregated discovery** | (stable) **Two** requests, `/api` and `/apis`, sent with `Accept: application/json;v=v2;g=apidiscovery.k8s.io;as=APIGroupDiscoveryList`, return everything. Supports ETag and protobuf. kubectl uses it. |
| **OpenAPI v2** | `/openapi/v2`: one large document with full schemas. Lossy: drops `default`, `nullable`, `oneOf`… |
| **OpenAPI v3** | `/openapi/v3`: an index of group versions. Each one points to `/openapi/v3/apis/<g>/<v>?hash=…`, which is **immutable**, cached for a year, and redirects when the hash is stale. Lossless, and the **preferred** form. |
| **Validation warning** | OpenAPI rules are incomplete. Only the server knows everything, so use `kubectl apply --dry-run=server`. |
| **Protobuf** | `application/vnd.kubernetes.protobuf`: a compact binary encoding, mainly for traffic inside the cluster. |
| **Persistence** | Objects are serialized into **etcd**. See `../components` and `../working-with-objects/storage-version`. |
| **Groups and versions** | Versioning is per **API** (group/version), not per field. All versions of a resource are representations of the **same** stored data. GA (`v1`) is a strong compatibility promise, beta data is converted forward, and alpha may break. |
| **Extension** | CustomResourceDefinitions, or an aggregation layer (an extra API server). Both show up in discovery. |

## The demo app
There's no app. Namespace `api-demo`, a JSON object [01-configmap.json](01-configmap.json), and [proxy.sh](proxy.sh), which runs `kubectl proxy` on `localhost:8001` so curl can reach the API with your credentials.

---

## Step 1
```bash
cd concepts/overview/kubernetes-api
kubectl apply -f 00-namespace.yaml
./proxy.sh start
A=http://localhost:8001
```

## Lab 1 – CRUD with plain HTTP
```bash
curl -s -X POST -H 'Content-Type: application/json' -d @01-configmap.json \
  $A/api/v1/namespaces/api-demo/configmaps -o /dev/null -w '%{http_code}\n'          # 201 Created
curl -s $A/api/v1/namespaces/api-demo/configmaps/from-curl | jq -c '{kind, name: .metadata.name, data}'
curl -s -X PATCH -H 'Content-Type: application/merge-patch+json' -d '{"data":{"patched":"yes"}}' \
  $A/api/v1/namespaces/api-demo/configmaps/from-curl | jq -c .data                     # {"created-with":"plain HTTP POST","patched":"yes"}
curl -s "$A/api/v1/namespaces/api-demo/configmaps?watch=true" &                        # a WATCH is just a long GET
curl -s -X DELETE $A/api/v1/namespaces/api-demo/configmaps/from-curl -o /dev/null -w '%{http_code}\n'   # 200 (the watch prints a DELETED event)
kill %1
```
Compare with what kubectl sends: `kubectl get cm -n api-demo -v=6 2>&1 | grep Response`.

## Lab 2 – Unaggregated discovery
```bash
curl -s $A/api  | jq -c .                                             # {"kind":"APIVersions","versions":["v1"],...}   the core group
curl -s $A/apis | jq -r '.kind, (.groups|length)'                     # APIGroupList, 21 groups
curl -s $A/apis | jq -c '.groups[] | select(.name=="apps")'
#   {"name":"apps","versions":[{"groupVersion":"apps/v1","version":"v1"}],"preferredVersion":{...}}   (same shape as the docs example)
curl -s $A/apis/apps/v1 | jq -c '.resources[] | select(.name=="deployments") | {name, namespaced, kind, verbs, shortNames}'
#   {"name":"deployments","namespaced":true,"kind":"Deployment","verbs":["create","delete",...,"watch"],"shortNames":["deploy"]}
```
Name, scope, verbs, alternative names and kind: everything the docs list. You need **one extra request per group version** to see the resources.

## Lab 3 – Aggregated discovery
```bash
H='Accept: application/json;v=v2;g=apidiscovery.k8s.io;as=APIGroupDiscoveryList'
curl -s -H "$H" $A/apis | jq -r '.kind, (.items|length)'              # APIGroupDiscoveryList, 21
curl -s -H "$H" $A/apis | jq -c '.items[] | select(.metadata.name=="apps") | .versions[0].resources[] | select(.resource=="deployments") | {resource, scope, verbs, shortNames, kind: .responseKind.kind}'
curl -s -D - -o /dev/null -H "$H" $A/apis | grep -i -E 'etag|content-type'      # ETag supported
```
How many requests does kubectl need to learn every resource? Use an empty cache so it can't cheat:
```bash
kubectl api-resources --cache-dir=$(mktemp -d) -v=6 2>&1 | grep '"Response"' | cut -c1-150
#   GET .../api?timeout=32s   200 OK
#   GET .../apis?timeout=32s  200 OK          <- 2 requests total, thanks to aggregated discovery
```

## Lab 4 – OpenAPI v2 and v3
```bash
curl -s $A/openapi/v2 -o /tmp/oa2.json -w '%{size_download} bytes\n'           # ~2.3 MB, one document
jq -r '.swagger, (.paths|length), (.definitions|length)' /tmp/oa2.json          # 2.0, ~430 paths, ~620 definitions
curl -s $A/openapi/v3 | jq -r '.paths | keys[]' | head                          # index: api, api/v1, apis/apps/v1, ...
U=$(curl -s $A/openapi/v3 | jq -r '.paths["apis/apps/v1"].serverRelativeURL'); echo $U
curl -s -D - -o /tmp/oa3.json "$A$U" | grep -i -E '^HTTP|cache-control|expires'
#   HTTP/1.1 200 OK / Cache-Control: public, immutable / Expires: <one year from now>
curl -s -o /dev/null -D - "$A/openapi/v3/apis/apps/v1?hash=0000" | grep -i -E '^HTTP|^location'
#   HTTP/1.1 301 Moved Permanently / Location: /openapi/v3/apis/apps/v1?hash=<current>     <- obsolete URL redirects
```
v3 is lossless and v2 isn't. Compare the same field:
```bash
U=$(curl -s $A/openapi/v3 | jq -r '.paths["api/v1"].serverRelativeURL'); curl -s "$A$U" > /tmp/oa3core.json
jq -c '.components.schemas["io.k8s.api.core.v1.ServicePort"].properties.protocol | {default, enum}' /tmp/oa3core.json
#   {"default":"TCP","enum":["SCTP","TCP","UDP"]}
jq -c '.definitions["io.k8s.api.core.v1.ServicePort"].properties.protocol | {default, enum}' /tmp/oa2.json
#   {"default":null,"enum":["SCTP","TCP","UDP"]}     <- "default" dropped in v2
echo "v3: $(grep -o '"default":' /tmp/oa3core.json | wc -l)  v2: $(grep -o '"default":' /tmp/oa2.json | wc -l)"     # e.g. 290 vs 3
rm -f /tmp/oa2.json /tmp/oa3.json /tmp/oa3core.json
```
`kubectl explain` reads this OpenAPI data: `kubectl explain deployment.spec.replicas`.

## Lab 5 – OpenAPI validation is incomplete
[02-schema-valid-but-invalid.yaml](02-schema-valid-but-invalid.yaml) has the right **types** everywhere, but a selector that doesn't match its labels and `containerPort: 70000`.
```bash
kubectl apply -f 02-schema-valid-but-invalid.yaml --dry-run=client     # deployment.apps/looks-fine created (dry run)   <- schema check passes
kubectl apply -f 02-schema-valid-but-invalid.yaml --dry-run=server
#   * spec.template.metadata.labels: Invalid value: {"app":"two"}: `selector` does not match template `labels`
#   * spec.template.spec.containers[0].ports[0].containerPort: Invalid value: 70000: must be between 1 and 65535, inclusive
```
This is the docs' warning: for complete validation, including admission, use `--dry-run=server`.

## Lab 6 – Protobuf
```bash
curl -s -H 'Accept: application/vnd.kubernetes.protobuf' $A/api/v1/namespaces/default/services/kubernetes | head -c 24 | od -c | head -2
#   k 8 s \0 \n \r \n 002 v 1 022 \a S e r v i c e ...      <- "k8s\0" magic + protobuf envelope
curl -s -H 'Accept: application/vnd.kubernetes.protobuf' $A/api/v1/namespaces/default/services/kubernetes -o /dev/null -w 'protobuf %{size_download} bytes\n'   # ~640
curl -s $A/api/v1/namespaces/default/services/kubernetes -o /dev/null -w 'json     %{size_download} bytes\n'                                                     # ~1690
```
Controllers and the kubelet use protobuf because it's smaller and faster. It's the same encoding etcd stores, which is why you needed `strings` in the components lab.

## Lab 7 – API groups and versions
```bash
curl -s $A/apis | jq -r '.groups[] | select((.versions|length)>1) | "\(.name): \([.versions[].version]|join(",")) preferred=\(.preferredVersion.version)"'
#   autoscaling: v2,v1 preferred=v2          <- one resource, two served versions, same stored data
kubectl get endpoints -n default
#   Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice    <- deprecation policy in action
kubectl api-versions | grep -E 'alpha|beta'    # any non-GA APIs enabled on this cluster
```
The HPA example, created through v1 and read through v2, is in `../working-with-objects/names` (Lab 3).

## Lab 8 – Extensions show up in discovery
```bash
kubectl apply -f ../working-with-objects/storage-version/crontab-crd.yaml
curl -s $A/apis/example.com | jq -c '{name, versions: [.versions[].version], preferred: .preferredVersion.version}'
#   {"name":"example.com","versions":["v1","v1beta1"],"preferred":"v1"}
kubectl api-resources --api-group=example.com
kubectl delete crd crontabs.example.com
curl -s $A/apis/apiregistration.k8s.io/v1/apiservices | jq -r '.items[].metadata.name' | head   # every group version is an APIService (aggregation layer)
```

---

## Useful commands
```bash
kubectl get --raw /apis/apps/v1 | jq .          # GET any API path without a proxy
kubectl api-resources -o wide                   # discovery, as a table
kubectl api-versions
kubectl explain <kind>.<field> --recursive      # OpenAPI schema
kubectl <cmd> -v=6                              # show the HTTP requests kubectl makes (-v=8 adds bodies)
```

## Cleanup
```bash
./cleanup.sh       # stops the proxy, deletes api-demo
```
