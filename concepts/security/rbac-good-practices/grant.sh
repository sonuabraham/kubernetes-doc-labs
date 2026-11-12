#!/usr/bin/env bash
# grant.sh <scope:ns|cluster> <rule-json>   - replaces the attacker's single permission with exactly this rule
set -euo pipefail
scope=$1; rule=$2
kubectl delete role,rolebinding -n rbac-demo -l attacker-grant --ignore-not-found >/dev/null
kubectl delete clusterrole,clusterrolebinding -l attacker-grant --ignore-not-found >/dev/null
if [ "$scope" = ns ]; then
  kubectl apply -f - >/dev/null <<Y
{"apiVersion":"rbac.authorization.k8s.io/v1","kind":"Role","metadata":{"name":"attacker-grant","namespace":"rbac-demo","labels":{"attacker-grant":"1"}},"rules":[$rule]}
Y
  kubectl create rolebinding attacker-grant -n rbac-demo --role=attacker-grant --serviceaccount=rbac-demo:attacker >/dev/null
  kubectl label rolebinding attacker-grant -n rbac-demo attacker-grant=1 >/dev/null
else
  kubectl apply -f - >/dev/null <<Y
{"apiVersion":"rbac.authorization.k8s.io/v1","kind":"ClusterRole","metadata":{"name":"attacker-grant","labels":{"attacker-grant":"1"}},"rules":[$rule]}
Y
  kubectl create clusterrolebinding attacker-grant --clusterrole=attacker-grant --serviceaccount=rbac-demo:attacker >/dev/null
  kubectl label clusterrolebinding attacker-grant attacker-grant=1 >/dev/null
fi
