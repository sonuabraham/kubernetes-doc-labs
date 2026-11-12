#!/usr/bin/env bash
# webhook-config.sh mutate|validate|slow-ignore|slow-fail  - (re)creates the matching webhook configuration with
# the good-practice knobs from the page: narrow rules (CREATE pods), namespaceSelector (only labelled namespaces),
# matchConditions (CEL), small timeoutSeconds, explicit failurePolicy, sideEffects None.
set -euo pipefail
cd "$(dirname "$0")"; CA=$(cat generated/ca.b64)
kind=Validating; path=/validate; fp=Fail; to=5; name=$1
case $1 in
  mutate) kind=Mutating; path=/mutate ;;
  validate) ;;
  slow-ignore) path=/slow; fp=Ignore; to=2 ;;
  slow-fail) path=/slow; fp=Fail; to=2 ;;
esac
kubectl delete mutatingwebhookconfiguration,validatingwebhookconfiguration -l lab=webhook-gp --ignore-not-found >/dev/null
[ "$1" = none ] && exit 0
kubectl apply -f - >/dev/null <<Y
apiVersion: admissionregistration.k8s.io/v1
kind: ${kind}WebhookConfiguration
metadata: {name: lab-$name, labels: {lab: webhook-gp}}
webhooks:
- name: $name.lab.example.com
  clientConfig:
    service: {namespace: webhook-system, name: lab-webhook, path: $path}
    caBundle: $CA
  rules:
  - {apiGroups: [""], apiVersions: ["*"], operations: ["CREATE"], resources: ["pods"], scope: Namespaced}   # all versions, narrow resource/op
  namespaceSelector: {matchLabels: {webhook-lab: enabled}}                                                  # never kube-system / webhook-system
  matchConditions:
  - name: skip-opted-out-pods
    expression: '!has(object.metadata.labels) || !("skip-webhook" in object.metadata.labels)'
  failurePolicy: $fp
  timeoutSeconds: $to
  sideEffects: None
  admissionReviewVersions: ["v1"]
$( [ $kind = Mutating ] && echo "  reinvocationPolicy: IfNeeded" )
Y
echo "lab-$name: ${kind}, path $path, failurePolicy $fp, timeout ${to}s"
