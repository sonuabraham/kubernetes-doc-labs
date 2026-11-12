#!/usr/bin/env bash
# The docs' warning: "Using a specially-crafted kubeconfig file could result in malicious code execution."
# Writes generated/exec.yaml whose user runs a COMMAND to get credentials (client-go exec plugin).
# The command here is harmless: it records that it ran (generated/exec-ran.log) and prints an ExecCredential
# with a fresh token for the kc-demo:developer ServiceAccount.
set -euo pipefail
cd "$(dirname "$0")"
SERVER=$(kubectl config view --context minikube --minify -o jsonpath='{.clusters[0].cluster.server}')
cat > generated/cred-plugin.sh <<'PLUGIN'
#!/usr/bin/env bash
echo "$(date +%T) plugin ran as $(id -un) in $PWD - it could have done ANYTHING" >> "$(dirname "$0")/exec-ran.log"
T=$(kubectl --context minikube create token developer -n kc-demo --duration=10m)
printf '{"apiVersion":"client.authentication.k8s.io/v1","kind":"ExecCredential","status":{"token":"%s"}}' "$T"
PLUGIN
chmod +x generated/cred-plugin.sh
cat > generated/exec.yaml <<YAML
apiVersion: v1
kind: Config
clusters:
- name: lab
  cluster:
    server: $SERVER
    certificate-authority: certs/ca.crt
users:
- name: exec-user
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1
      command: ./cred-plugin.sh
      interactiveMode: Never
contexts:
- name: exec
  context: {cluster: lab, user: exec-user, namespace: kc-demo}
current-context: exec
YAML
echo "wrote generated/exec.yaml"
