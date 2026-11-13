#!/usr/bin/env bash
# Non-interactive "kubectl edit configmap kube-dns-autoscaler": replace the whole scaling-params line.
#   ./set-params.sh 'linear: '"'"'{"coresPerReplica":2,"nodesPerReplica":16,"min":1,"preventSinglePointFailure":true}'"'"''
#   ./set-params.sh 'ladder: '"'"'{"coresToReplicas":[[1,1],[4,2],[8,3]],"nodesToReplicas":[[1,1],[2,2]]}'"'"''
# (the autoscaler picks the mode from the key name: linear or ladder)
export NEWLINE="$1"
KUBE_EDITOR='python3 -c "import os,re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r\"(?m)^  (linear|ladder): .*$\", \"  \"+os.environ[\"NEWLINE\"], s); open(p,\"w\").write(s)"' \
  kubectl edit configmap kube-dns-autoscaler --namespace=kube-system
kubectl get configmap kube-dns-autoscaler -n kube-system -o jsonpath='{.data}{"\n"}'
