#!/usr/bin/env python3
"""Non-interactive "kubectl edit cm": change one YAML document stored in a ConfigMap key.
   ./edit-cm.py <configmap> <data-key> '<python statement on d>'   [CTX=kubeadm-lab]
   e.g. ./edit-cm.py kubelet-config kubelet 'd["maxPods"]=50'"""
import json, os, subprocess, sys, yaml
cm, key, stmt = sys.argv[1:4]
k = ["kubectl", "--context", os.environ.get("CTX", "kubeadm-lab"), "-n", "kube-system"]
obj = json.loads(subprocess.run(k + ["get", "cm", cm, "-o", "json"], capture_output=True, check=True).stdout)
d = yaml.safe_load(obj["data"][key])
exec(stmt)
obj["data"][key] = yaml.safe_dump(d, sort_keys=False)
subprocess.run(k + ["replace", "-f", "-"], input=json.dumps(obj).encode(), check=True)
