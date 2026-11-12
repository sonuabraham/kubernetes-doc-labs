#!/usr/bin/env bash
# New profile with coordinated leader election: gate CoordinatedLeaderElection, API coordination.k8s.io/v1beta1,
# and leader election turned ON for controller-manager and scheduler (minikube defaults to --leader-elect=false).
minikube start -p cle-lab --memory 2048 --cpus 2 --kubernetes-version v1.37.0 \
  --feature-gates=CoordinatedLeaderElection=true \
  --extra-config=apiserver.runtime-config=coordination.k8s.io/v1beta1=true \
  --extra-config=controller-manager.leader-elect=true \
  --extra-config=scheduler.leader-elect=true
echo "When done: minikube stop -p cle-lab ; kubectl config use-context minikube"
