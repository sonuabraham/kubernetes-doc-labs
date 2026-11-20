#!/usr/bin/env bash
# Cleanup. The docs' block has two bugs that leave the Deny policy active: "validatingadmissionpolices" (typo) and the binding
# name (it is enforce-multiple-replicas-deployments-binding). Fixed here, plus the test Deployments/Namespaces of this lab.
kubectl delete validatingadmissionpolicies/enforce-multiple-replicas-deployments \
               validatingadmissionpolicybindings/enforce-multiple-replicas-deployments-binding --ignore-not-found
kubectl delete mutatingadmissionpolicies/default-pod-security-baseline \
               mutatingadmissionpolicybindings/default-pod-security-baseline --ignore-not-found
kubectl delete mutatingadmissionpolicies/default-pod-security-configurable \
               mutatingadmissionpolicybindings/default-pod-security-configurable --ignore-not-found
kubectl --namespace kube-system delete configmaps/default-pod-security-standard --ignore-not-found
kubectl delete namespaces example another-example yet-another-example one-more-example no-param-example --ignore-not-found
kubectl delete deployment one three four --ignore-not-found
