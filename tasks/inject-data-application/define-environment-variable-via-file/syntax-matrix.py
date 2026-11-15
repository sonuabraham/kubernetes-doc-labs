#!/usr/bin/env python3
"""NOT from the docs: one Pod per env-file syntax rule of the page (Pods ef-<case>). Usage:
   python3 syntax-matrix.py | kubectl apply -f -
Each Pod prints [$VAL] if the kubelet could parse the file, else it stays in CreateContainerConfigError."""
import json, sys
cases = {
  "plain":        "VAL='value'\n",
  "spaces":       "VAL = 'value'\n",
  "leading":      "   VAL='value'\n",
  "comment":      "# a comment\nVAL='value'\n",
  "blank":        "\nVAL='value'\n\n",
  "hash-inside":  "VAL='a # b'\n",
  "multiline":    "VAL='line1\nline2'\n",
  "no-newline":   "VAL='value'",
}
items = []
for name, content in cases.items():
    items.append({"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "ef-" + name},
      "spec": {"restartPolicy": "Never", "volumes": [{"name": "config", "emptyDir": {}}],
        "initContainers": [{"name": "w", "image": "busybox:1.36", "volumeMounts": [{"name": "config", "mountPath": "/data"}],
          "command": ["sh", "-c", 'cat > /data/config.env <<"X"\n' + content + ('\n' if not content.endswith('\n') else '') + 'X\n' if name != "no-newline" else "printf %s \"$C\" > /data/config.env"],
          "env": [{"name": "C", "value": content}]}],
        "containers": [{"name": "c", "image": "busybox:1.36", "command": ["sh", "-c", 'echo "[$VAL]"'],
          "env": [{"name": "VAL", "valueFrom": {"fileKeyRef": {"path": "config.env", "volumeName": "config", "key": "VAL", "optional": False}}}]}]}})
print(json.dumps({"apiVersion": "v1", "kind": "List", "items": items}))
