#!/usr/bin/env bash
# NOT from the docs: exercise lab-objects/cel-fields.yaml. Uses the raw API so the Status (code, reason, causes) is visible.
cd "$(dirname "$0")"
kubectl apply -f cel-fields.yaml >/dev/null && kubectl wait --for=condition=Established crd/limits.lab.example.com >/dev/null
P=/apis/lab.example.com/v1/namespaces/default/limits
try() {  # $1 = name, $2 = spec JSON
  printf '{"apiVersion":"lab.example.com/v1","kind":"Limit","metadata":{"name":"%s"},"spec":%s}' "$1" "$2" |
    kubectl create --raw $P -f - 2>&1 | grep -q '"kind":"Limit"' && { echo "  created"; return; }
  printf '{"apiVersion":"lab.example.com/v1","kind":"Limit","metadata":{"name":"%s"},"spec":%s}' "$1" "$2" |
    kubectl create -f - -o name 2>&1 | sed 's/^/  /'
}
echo "B33 messageExpression:"; try a '{"withMessageExpression":{"x":7,"maxLimit":5}}'
echo "B34 reason:";            try b '{"withReason":{"x":7,"maxLimit":5}}'
echo "B34 reason, HTTP status and causes:"
printf '{"apiVersion":"lab.example.com/v1","kind":"Limit","metadata":{"name":"b"},"spec":{"withReason":{"x":7,"maxLimit":5}}}' |
  kubectl create -f - -v=8 2>&1 | grep -oE 'Response Status: [0-9]+ [A-Za-z ]+|"causes":\[[^]]*\]' | head -2 | sed 's/^/  /'
echo "B35 fieldPath:";         try c '{"withFieldPath":{"maxLimit":5,"foo":{"test":{"x":7}}}}'
echo "B36 transition: create with low (never checked on create):"; try lvl '{"level":"low"}'
echo "  low -> high:";   kubectl patch limit lvl --type=merge -p '{"spec":{"level":"high"}}' 2>&1 | sed 's/^/  /'
echo "  low -> medium -> high:"; kubectl patch limit lvl --type=merge -p '{"spec":{"level":"medium"}}' >/dev/null && kubectl patch limit lvl --type=merge -p '{"spec":{"level":"high"}}' 2>&1 | sed 's/^/  /'
echo "optionalOldSelf: new object with foo=bar:"; try pin1 '{"pinned":{"foo":"bar"}}'
echo "  new object with foo=foo:"; try pin2 '{"pinned":{"foo":"foo"}}'
echo "  foo -> bar:"; kubectl patch limit pin2 --type=merge -p '{"spec":{"pinned":{"foo":"bar"}}}' 2>&1 | sed 's/^/  /'
kubectl delete limit --all >/dev/null
