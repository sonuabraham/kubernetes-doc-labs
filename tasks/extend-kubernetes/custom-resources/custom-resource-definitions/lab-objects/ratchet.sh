#!/usr/bin/env bash
# NOT from the docs: validation ratcheting. A CronTab with replicas 15 is created while the schema allows 20, then
# the docs' B23 schema (maximum 10, cronSpec pattern) plus a CEL rule is applied over it.
D=$(cd "$(dirname "$0")/.." && pwd)
kubectl apply -f - <<'Y'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: {name: crontabs.stable.example.com}
spec:
  group: stable.example.com
  scope: Namespaced
  names: {plural: crontabs, singular: crontab, kind: CronTab, shortNames: [ct]}
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              cronSpec: {type: string}
              image: {type: string}
              replicas: {type: integer, minimum: 1, maximum: 20}
Y
kubectl apply -f - <<'Y'
apiVersion: stable.example.com/v1
kind: CronTab
metadata: {name: old-object}
spec: {cronSpec: "* * * *", image: v1, replicas: 15}
Y
echo "--- tighten: the docs' B23 schema (max 10 + cronSpec pattern)"
kubectl apply -f "$D"/docs-examples/B23-validation.yaml
echo "1) change only image:";        kubectl patch ct old-object --type=merge -p '{"spec":{"image":"v2"}}'
echo "2) change replicas 15 -> 16:"; kubectl patch ct old-object --type=merge -p '{"spec":{"replicas":16}}' 2>&1
echo "3) change replicas 15 -> 9:";  kubectl patch ct old-object --type=merge -p '{"spec":{"replicas":9}}'
echo "4) back to 15:";               kubectl patch ct old-object --type=merge -p '{"spec":{"replicas":15}}' 2>&1
echo "5) new object, same bad values:"
kubectl apply -f - 2>&1 <<'Y'
apiVersion: stable.example.com/v1
kind: CronTab
metadata: {name: new-object}
spec: {cronSpec: "* * * *", image: v1, replicas: 15}
Y
kubectl delete ct old-object --ignore-not-found
