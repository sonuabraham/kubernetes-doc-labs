#!/usr/bin/env bash
# Copy the docs' templates (templates/, verbatim) into work/ with the <placeholders> filled in.
#   MASTER_IP          = the minikube node IP (what clients dial)
#   MASTER_CLUSTER_IP  = first IP of --service-cluster-ip-range = ClusterIP of the "kubernetes" Service
set -e; cd "$(dirname "$0")"; mkdir -p work
MASTER_IP=${MASTER_IP:-$(minikube ip)}
MASTER_CLUSTER_IP=${MASTER_CLUSTER_IP:-$(kubectl get svc kubernetes -n default -o jsonpath='{.spec.clusterIP}')}
for f in templates/*; do
  sed -e "s/<MASTER_IP>/$MASTER_IP/g" -e "s/<MASTER_CLUSTER_IP>/$MASTER_CLUSTER_IP/g" \
      -e "s/<country>/AU/; s/<state>/NSW/; s/<city>/Sydney/; s/<organization>/Lab/; s/<organization unit>/k8s-docs/" \
      "$f" > "work/$(basename "$f")"
done
echo "MASTER_IP=$MASTER_IP MASTER_CLUSTER_IP=$MASTER_CLUSTER_IP -> $(ls work | tr '\n' ' ')"
