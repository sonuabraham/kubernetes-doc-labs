#!/usr/bin/env bash
# The docs' cleanup + everything the extra labs created (default namespace).
cd "$(dirname "$0")"
kubectl delete configmaps/game-config configmaps/game-config-2 configmaps/game-config-3 configmaps/game-config-env-file \
  configmaps/config-multi-env-files configmaps/special-config configmaps/env-config configmaps/a-config \
  configmaps/binary-demo configmaps/frozen --ignore-not-found
kubectl delete configmap -l 'game-config in (config-4,config-5)'
kubectl delete configmap $(kubectl get cm -o name | grep -o 'special-config-2-.*') --ignore-not-found 2>/dev/null
kubectl delete pod dapi-test-pod --now --ignore-not-found
kubectl delete -f restrictions.yaml -f update-demo.yaml --ignore-not-found --now
rm -f kustomization.yaml
