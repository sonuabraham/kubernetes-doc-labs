#!/usr/bin/env bash
# scrape.sh <file> - fetch kube-state-metrics' /metrics once (curl Pod pinned to the real node) into <file>
kubectl delete pod curl -n ksm --grace-period=0 --force >/dev/null 2>&1
kubectl run curl -n ksm --image=curlimages/curl:8.10.1 --restart=Never --overrides='{"spec":{"nodeName":"minikube"}}' -- -s http://kube-state-metrics.ksm:8080/metrics >/dev/null
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/curl -n ksm --timeout=60s >/dev/null
kubectl logs curl -n ksm | cat > "${1:-ksm.txt}"      # "| cat": in some shells kubectl output written straight to a file is lost
