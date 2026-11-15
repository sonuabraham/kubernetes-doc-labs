#!/usr/bin/env bash
# NOT from the docs. Writes broken COPIES of the current minikube kubeconfig into ./broken/ (gitignored) -
# one per failure the page describes - so each error message can be seen. Your real ~/.kube/config is not touched.
set -euo pipefail
cd "$(dirname "$0")"; mkdir -p broken
kubectl config view --minify --flatten | cat > broken/good.yaml
SRV=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
sed "s|$SRV|https://192.168.58.2:9443|"   broken/good.yaml > broken/wrong-port.yaml       # nothing listens there
sed "s|$SRV|https://10.255.255.1:8443|"   broken/good.yaml > broken/unreachable.yaml      # blackhole: like a dropped VPN
sed "s|$SRV|https://127.0.0.1:8443|"      broken/good.yaml > broken/wrong-host.yaml       # local port - nothing there
# a CA that did not sign the API server certificate
openssl req -x509 -newkey rsa:2048 -nodes -keyout broken/other-ca.key -out broken/other-ca.crt -days 1 -subj /CN=other-ca 2>/dev/null
python3 - <<'PY'
import base64, re
good=open('broken/good.yaml').read()
ca=base64.b64encode(open('broken/other-ca.crt','rb').read()).decode()
open('broken/wrong-ca.yaml','w').write(re.sub(r'certificate-authority-data: \S+', 'certificate-authority-data: '+ca, good))
# user with a bogus bearer token instead of the client certificate
u=re.sub(r'    client-certificate-data: \S+\n    client-key-data: \S+\n', '    token: not-a-real-token\n', good)
open('broken/bad-token.yaml','w').write(u)
# user whose auth comes from an exec helper that is not installed (the docs' kubectl-oidc-login case)
e=re.sub(r'    client-certificate-data: \S+\n    client-key-data: \S+\n',
  '    exec:\n      apiVersion: client.authentication.k8s.io/v1\n      command: kubectl-oidc_login\n      args: [get-token]\n      interactiveMode: Never\n', good)
open('broken/missing-helper.yaml','w').write(e)
PY
ls broken
