#!/usr/bin/env python3
"""NOT from the docs. Wrap a schema fragment from the page into a throwaway CRD and print what the API server says.

  ./frag.py SCHEMA.yaml [OBJECT.yaml]

SCHEMA.yaml is used as spec.versions[0].schema.openAPIV3Schema of CRD frags.lab.example.com (kind Frag,
namespaced). A leading `openAPIV3Schema:` key is unwrapped. If the fragment has no top-level `type`, it is
first tried exactly as written; the CRD result (created / rejected + reasons) is printed.
If OBJECT.yaml is given (only the fields under the root, e.g. `spec: …` or `json: …`), a Frag named `test`
with that content is created with --validate=false and the stored object is printed (to show pruning/defaulting).
The CRD is deleted at the end."""
import json, subprocess, sys, yaml
def sh(args, inp=None):
    r = subprocess.run(args, input=inp, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()
schema = yaml.safe_load(open(sys.argv[1]))
if isinstance(schema, dict) and list(schema) == ['openAPIV3Schema']:
    schema = schema['openAPIV3Schema']
crd = {"apiVersion": "apiextensions.k8s.io/v1", "kind": "CustomResourceDefinition",
       "metadata": {"name": "frags.lab.example.com"},
       "spec": {"group": "lab.example.com", "scope": "Namespaced",
                "names": {"plural": "frags", "singular": "frag", "kind": "Frag"},
                "versions": [{"name": "v1", "served": True, "storage": True, "schema": {"openAPIV3Schema": schema}}]}}
sh(["kubectl", "delete", "crd", "frags.lab.example.com", "--ignore-not-found", "--wait=true"])
rc, out = sh(["kubectl", "create", "-f", "-"], json.dumps(crd))
print("CRD:", "created" if rc == 0 else "REJECTED")
if rc != 0:
    import re
    errs = re.findall(r'(spec\.validation[^,\]]*?: (?:Required value|Forbidden|Invalid value|Unsupported value)[^,\]]*)', out)
    for e in dict.fromkeys(errs) or [out[-400:]]:
        print("   ", e.strip()[:300])
    sys.exit(0)
sh(["kubectl", "wait", "--for=condition=Established", "crd/frags.lab.example.com"])
rc, out = sh(["kubectl", "get", "crd", "frags.lab.example.com", "-o",
              "jsonpath={range .status.conditions[*]}{.type}={.status} {.message}{\"\\n\"}{end}"])
for l in out.splitlines():
    if l.startswith("NonStructural") or "Violation" in l: print("   ", l)
if len(sys.argv) > 2:
    body = yaml.safe_load(open(sys.argv[2]))
    obj = {"apiVersion": "lab.example.com/v1", "kind": "Frag", "metadata": {"name": "test"}, **body}
    rc, out = sh(["kubectl", "create", "--validate=false", "-o", "json", "-f", "-"], json.dumps(obj))
    if rc == 0:
        o = json.loads(out); [o.pop(k) for k in ("apiVersion", "kind", "metadata")]
        print("stored:", json.dumps(o))
    else:
        print("object REJECTED:", out[-400:])
sh(["kubectl", "delete", "crd", "frags.lab.example.com", "--wait=true"])
