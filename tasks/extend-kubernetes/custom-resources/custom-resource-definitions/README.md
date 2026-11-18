# Extend the Kubernetes API with CustomResourceDefinitions – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/

> Runs on the default **minikube** cluster (v1.37), `default` namespace. The page has 52 YAML blocks:
> - [docs-examples/](docs-examples/) – **every** ```yaml block of the page, **verbatim**, as `BNN-<section>.yaml`, written by
>   [extract-examples.py](extract-examples.py). Full manifests are applied as is; schema **fragments** go through the harness below.
> - [frag.py](frag.py) – wraps a schema fragment into a throwaway CRD `frags.lab.example.com`, prints whether the API server accepts it,
>   and optionally creates an object to show what gets stored (pruning, defaulting).
> - [lab-objects/](lab-objects/) – test objects and small scripts (all **not from the docs**): [ratchet.sh](lab-objects/ratchet.sh),
>   [cel-fields.yaml](lab-objects/cel-fields.yaml) + [cel-fields.sh](lab-objects/cel-fields.sh), fixed versions of broken examples.
> - [shirt-resource-definition.yaml](shirt-resource-definition.yaml), [shirt-resources.yaml](shirt-resources.yaml) – docs example files, verbatim.
>
> Concept background and etcd views: [concepts/…/custom-resources](../../../../concepts/extend-kubernetes/api-extension/custom-resources/).

## Found (docs vs. v1.37)

| # | Docs | Reality |
|---|---|---|
| 1 | RawExtension example B20 (`x-kubernetes-embedded-resource` without `type`) | **rejected**: `must be object if x-kubernetes-embedded-resource is true` → [rawextension-fixed-schema.yaml](lab-objects/rawextension-fixed-schema.yaml) |
| 2 | B39 "same estimated cost as the previous example" | **syntax error**, the rule has an extra `)`: `self.contains('a string'))` → [B39-fixed.yaml](lab-objects/B39-fixed.yaml) is accepted |
| 3 | B40 "the following rule is allowed" | **rejected**: `x-kubernetes-validations` is indented as a *property* next to `foo` (`cannot unmarshal array into … properties`) → [B40-fixed.yaml](lab-objects/B40-fixed.yaml) |
| 4 | B33 `messageExpression: '"x exceeded max limit of " + string(self.maxLimit)'` | **rejected by the cost estimator** (`estimated messageExpression cost exceeds budget by factor of more than 100x`). `string(int)` alone or `"…%d".format([self.maxLimit])` pass. |
| 5 | "`additionalProperties` cannot be set to `false`" | accepted **and enforced** (`spec.anything in body is a forbidden property`); only *together with* `properties` is it rejected |
| 6 | Non-structural schemas "are reported in the `NonStructural` condition" | v1 CRDs with such schemas are **rejected at create time**; all 6 violations of example 3 are listed in the error |
| 7 | Pruning demo: "`kubectl` also checks for unknown fields" (client side) | it's **server-side** field validation now: `strict decoding error: unknown field "spec.someRandomField"` (also with `--validate=strict`) |
| 8 | `reason`: "the HTTP status code … will match the reason" | the Status stays `Invalid` (422); only `details.causes[].reason` becomes `FieldValueForbidden` |
| 9 | Categories: `kubectl get all` shows the CronTab | right after adding `categories`, kubectl's **cached discovery** didn't include it; the next call (after `kubectl api-resources`) did |

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| CRD | defines group/version/kind/plural/scope; the API server serves `/apis/<group>/<version>/…/<plural>` |
| Structural schema | required in `apiextensions.k8s.io/v1`: types everywhere, no types/defaults inside `allOf/anyOf/oneOf/not`, `metadata` only `name`/`generateName` |
| Pruning | unknown fields are dropped before storing, except under `x-kubernetes-preserve-unknown-fields` |
| Validation | OpenAPI (`pattern`, `minimum`…) + CEL `x-kubernetes-validations` (`rule`, `message`/`messageExpression`, `reason`, `fieldPath`, `oldSelf` transition rules, `optionalOldSelf`) |
| Ratcheting | unchanged invalid fields of existing objects don't block updates |
| Defaulting | `default:` applied on requests **and when reading from etcd** (not written back) |
| Subresources | `status` (separate endpoint, generation ignores status), `scale` (`kubectl scale`, HPA, PDB) |

---

## Lab 1 – Create, use, delete (docs)
```bash
cd tasks/extend-kubernetes/custom-resources/custom-resource-definitions
E=docs-examples
kubectl apply -f $E/B01-create-a-customresourcedefinit.yaml
kubectl get --raw /apis/stable.example.com/v1 | jq -c '[.resources[] | {name, shortNames, namespaced}]'
#   [{"name":"crontabs","shortNames":["ct"],"namespaced":true}]
kubectl apply -f $E/B02-create-custom-objects.yaml
kubectl get crontab                      # my-new-cron-object   0s
kubectl get ct -o yaml | grep -E 'cronSpec|image'
kubectl delete -f $E/B01-create-a-customresourcedefinit.yaml
kubectl get crontabs
#   Error from server (NotFound): Unable to list "stable.example.com/v1, Resource=crontabs": the server could not find the requested resource
```

## Lab 2 – Structural schemas (docs examples through the harness)
```bash
for b in B04 B05 B06 B07 B08 B09; do echo "## $b"; ./frag.py $E/$b-*.yaml; done
```
| Block | Docs says | Result |
|---|---|---|
| B04 `allOf: properties: foo` | non-structural (rule 2) | REJECTED: `properties[foo]: Required value: because it is defined in …allOf[0].properties[foo]` (+ root type missing) |
| B05 corrected | structural | still REJECTED here: `properties[foo].type` and root `type` missing (the docs' `# ...` placeholders) |
| B06 / B07 (arrays) | non-structural / corrected | REJECTED / REJECTED (same placeholder reason) |
| B08 example 3 | 6 violations | REJECTED with exactly those 6 (anyOf description, anyOf bar type, bar not outside, foo type, metadata beyond name, root type) |
| B09 structural counterpart | structural | **created**; `bar: 41` → `should be greater than or equal to 42`; name `test` → `metadata.name … should match '^a'` |

## Lab 3 – Pruning, preserve-unknown-fields, IntOrString, RawExtension (docs)
```bash
kubectl apply -f $E/B01-create-a-customresourcedefinit.yaml
kubectl create -f $E/B10-field-pruning.yaml
#   … strict decoding error: unknown field "spec.someRandomField"      <- server-side field validation (Found #7)
kubectl create --validate=false -f $E/B10-field-pruning.yaml -o yaml | sed -n '/^spec:/,$p'
#   spec:
#     cronSpec: '* * * * */5'
#     image: my-awesome-cron-image                       <- someRandomField pruned
kubectl delete ct my-new-cron-object
./frag.py $E/B12-controlling-pruning.yaml lab-objects/any-json.yaml     # stored: {"json": {"a": 1, "b": ["x","y"], "c": {"d": "e"}}}
./frag.py $E/B13-controlling-pruning.yaml lab-objects/json-string.yaml  # REJECTED: json in body must be of type object: "string"
./frag.py $E/B14-controlling-pruning.yaml $E/B15-controlling-pruning.yaml
#   stored: {"json": {"spec": {"bar": "def", "foo": "abc"}, "status": {"something": "x"}}}     <- = B16 in the docs
./frag.py $E/B17-intorstring.yaml lab-objects/int.yaml      # stored: {"foo": 42}
./frag.py $E/B17-intorstring.yaml lab-objects/string.yaml   # stored: {"foo": "50%"}
./frag.py $E/B17-intorstring.yaml lab-objects/bool.yaml     # REJECTED: foo in body must be of type integer,string: "boolean"
./frag.py $E/B18-intorstring.yaml; ./frag.py $E/B19-intorstring.yaml        # both created (the two allowed anyOf/allOf patterns)
./frag.py $E/B20-rawextension.yaml
#   REJECTED: properties[foo].type: Required value: must be object if x-kubernetes-embedded-resource is true    (Found #1)
./frag.py lab-objects/rawextension-fixed-schema.yaml lab-objects/embedded-pod.yaml
#   stored: {"foo": {"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "inner"}, "spec": {…}}}   <- unknown metadata field pruned
./frag.py lab-objects/rawextension-fixed-schema.yaml lab-objects/embedded-no-kind.yaml
#   REJECTED: foo.apiVersion: Required value, foo.kind: Required value
```

## Lab 4 – Finalizers (docs)
```bash
kubectl apply -f lab-objects/crontab-finalizer.yaml           # B22 + name
kubectl delete crontab with-finalizer --wait=false
kubectl get ct with-finalizer -o jsonpath='{.metadata.deletionTimestamp} {.metadata.finalizers}'
#   2026-11-18T10:24:14Z ["stable.example.com/finalizer"]          <- still there
kubectl patch ct with-finalizer --type=json -p '[{"op":"add","path":"/metadata/finalizers/-","value":"stable.example.com/another"}]'
#   metadata.finalizers: Forbidden: no new finalizers can be added if the object is being deleted
kubectl patch ct with-finalizer --type=merge -p '{"spec":{"image":"changed"}}'     # patched (spec still editable)
kubectl delete ct with-finalizer --grace-period=0 --force --wait=false              # "force deleted" … but:
kubectl get ct with-finalizer                                                       # still listed ("impossible to force the deletion")
kubectl patch ct with-finalizer --type=json -p '[{"op":"remove","path":"/metadata/finalizers/0"}]'
kubectl get ct with-finalizer                                                       # NotFound
```

## Lab 5 – OpenAPI validation and ratcheting (docs)
```bash
kubectl apply -f $E/B23-validation.yaml
kubectl apply -f $E/B24-validation.yaml
#   The CronTab "my-new-cron-object" is invalid:
#   * spec.replicas: Invalid value: 15: spec.replicas in body should be less than or equal to 10
#   * spec.cronSpec: Invalid value: "* * * *": spec.cronSpec in body should match '^(\d+|\*)(/\d+)?(\s+(\d+|\*)(/\d+)?){4}$'
kubectl apply -f $E/B25-validation.yaml       # created
kubectl delete ct my-new-cron-object
```
Forbidden schema features (via `frag.py`): `uniqueItems: true` → `cannot be set to true since the runtime complexity becomes quadratic`;
`$ref` → `$ref is not supported`; `readOnly` → `unknown field`; `additionalProperties: false` → **accepted** (Found #5).
```bash
lab-objects/ratchet.sh      # object created with replicas 15 + bad cronSpec under a looser schema, then B23 applied
#   1) change only image:          patched                <- both invalid fields unchanged: ratcheted
#   2) change replicas 15 -> 16:   spec.replicas … should be less than or equal to 10
#   3) change replicas 15 -> 9:    patched
#   4) back to 15:                 rejected               <- once fixed, it can't go back
#   5) new object, same bad values: rejected (both errors)
```

## Lab 6 – CEL validation rules (docs)
```bash
./frag.py $E/B26-validation-rules.yaml lab-objects/replicas-bad.yaml
#   spec: Invalid value: replicas should be smaller than or equal to maxReplicas.
./frag.py lab-objects/B26-no-message.yaml lab-objects/replicas-bad.yaml
#   spec: Invalid value: failed rule: self.replicas <= self.maxReplicas
```
Compile errors (CRD rejected), as in the docs:
```
self == true               → compilation failed: ERROR: <input>:1:6: found no matching overload for '_==_' applied to '(int, bool)'
self.nonExistingField > 0  → compilation failed: ERROR: <input>:1:5: undefined field 'nonExistingField'
has(self)                  → compilation failed: ERROR: <input>:1:5: invalid argument to has() macro
```
Scope examples B28–B32 (root, object, map, array, scalar): all **created**. Cost examples:
| Block | Docs | Result |
|---|---|---|
| B37 `self.all(x, x.contains('a string'))`, no limits | rejected | REJECTED: `estimated rule cost total for entire OpenAPIv3 schema exceeds budget by factor of more than 100x` |
| B38 + `maxItems: 25`, `maxLength: 10` | allowed | created |
| B39 rule on items | allowed | **REJECTED: Syntax error** (extra `)`, Found #2); fixed → created |
| B40 non-nested `self.all(x, x == 5)` | allowed | **REJECTED** (mis-indented, Found #3); fixed → created |
| B41 nested arrays | rejected | REJECTED (cost) |

```bash
./frag.py lab-objects/B33-as-documented.yaml lab-objects/me-obj.yaml     # REJECTED: cost (Found #4)
lab-objects/cel-fields.sh
#   B33 messageExpression:  spec.withMessageExpression: Invalid value: x exceeded max limit of 5      (format() variant)
#   B34 reason:             spec.withReason: Forbidden: failed rule: self.x <= self.maxLimit
#   B34 reason, HTTP status and causes:  "causes":[{"reason":"FieldValueForbidden",…,"field":"spec.withReason"}]   (Status reason still "Invalid")
#   B35 fieldPath:          spec.withFieldPath.foo.test.x: Invalid value: failed rule: …    <- error points at .foo.test.x
#   B36 transition: create with low → created (transition rules never run on create)
#     low -> high:          spec.level: Invalid value: "high": cannot transition directly between 'low' and 'high'
#     low -> medium -> high: patched
#   optionalOldSelf: new object foo=bar → rejected; foo=foo → created; foo -> bar → rejected
```

## Lab 7 – Defaulting and nullable (docs)
```bash
kubectl apply -f $E/B42-defaulting.yaml
kubectl apply -f $E/B43-defaulting.yaml
kubectl get ct my-new-cron-object -o jsonpath='{.spec}'
#   {"cronSpec":"5 0 * * *","image":"my-awesome-cron-image","replicas":1}        <- = B44
```
- A `spec` default of `{"replicas": "foo", "badger": 1}` (the page's counter-example) → `must not have unknown fields` and `replicas in body must be of type integer`.
- **Defaults on read:** an object stored under B01 (no defaults) as `spec: {image: x}`; after applying B42, `kubectl get` shows
  `{"cronSpec":"5 0 * * *","image":"x","replicas":1}`, while etcd still holds `"spec":{"image":"x"}`
  (`../../../../concepts/extend-kubernetes/api-extension/custom-resources/etcd-get.sh /registry/stable.example.com/crontabs/default/stored-early`).
```bash
./frag.py $E/B45-defaulting-and-nullable.yaml $E/B46-defaulting-and-nullable.yaml
#   stored: {"spec": {"bar": null, "foo": "default"}}      <- = B47 (baz pruned)
kubectl explain crontab.spec.replicas      # works: the schema is published in OpenAPI
```

## Lab 8 – Printer columns, field selectors (docs)
```bash
kubectl apply -f $E/B48-additional-printer-columns.yaml
kubectl apply -f $E/B25-validation.yaml
kubectl get crontab my-new-cron-object
#   NAME                 SPEC          REPLICAS   AGE
#   my-new-cron-object   * * * * */5   5          0s
kubectl apply -f shirt-resource-definition.yaml -f shirt-resources.yaml
kubectl get shirts.stable.example.com                                          # example1 blue S / example2 blue M / example3 green M
kubectl get shirts.stable.example.com --field-selector spec.color=blue         # example1, example2
kubectl get shirts.stable.example.com --field-selector spec.color=green,spec.size=M    # example3
kubectl get shirts.stable.example.com --field-selector spec.size!=M            # example1   (!= works too)
kubectl get crontabs --field-selector spec.image=x
#   … field label not supported: spec.image        <- only declared selectableFields (+ metadata.name/namespace)
```

## Lab 9 – Status and scale subresources (docs)
```bash
kubectl delete ct --all
kubectl apply -f $E/B49-scale-subresource.yaml
kubectl apply -f $E/B50-scale-subresource.yaml
kubectl get --raw /apis/stable.example.com/v1 | jq -r '.resources[].name'       # crontabs  crontabs/status  crontabs/scale
kubectl scale --replicas=5 crontabs/my-new-cron-object
kubectl get crontabs my-new-cron-object -o jsonpath='{.spec.replicas}'          # 5
kubectl get --raw /apis/stable.example.com/v1/namespaces/default/crontabs/my-new-cron-object/scale | jq -c '{kind,spec,status}'
#   {"kind":"Scale","spec":{"replicas":5},"status":{"replicas":0}}               <- no status yet: 0
kubectl patch ct my-new-cron-object --type=merge -p '{"status":{"replicas":5,"labelSelector":"app=cron"}}'
#   patched (no change)                                                          <- status ignored on the main resource
kubectl patch ct my-new-cron-object --subresource=status --type=merge -p '{"spec":{"image":"ignored"},"status":{"replicas":4,"labelSelector":"app=cron"}}'
kubectl get ct my-new-cron-object -o jsonpath='image={.spec.image} status={.status} generation={.metadata.generation}'
#   image=my-awesome-cron-image status={"labelSelector":"app=cron","replicas":4} generation=2    <- spec ignored on /status; generation unchanged
kubectl patch ct my-new-cron-object --type=merge -p '{"spec":{"image":"v2"}}'   # generation → 3
kubectl get --raw /apis/stable.example.com/v1/namespaces/default/crontabs/my-new-cron-object/scale | jq -c .status
#   {"replicas":4,"selector":"app=cron"}
```

## Lab 10 – Categories (docs)
```bash
kubectl delete ct --all
kubectl apply -f $E/B51-categories.yaml
kubectl apply -f $E/B52-categories.yaml
kubectl get all                  # first call: only service/kubernetes (stale discovery cache, Found #9)
kubectl api-resources --categories=all | grep crontabs     # crontabs   ct   stable.example.com/v1   true   CronTab
kubectl get all
#   NAME                                            AGE
#   crontab.stable.example.com/my-new-cron-object   9s
```

## Cleanup
```bash
./cleanup.sh
```
