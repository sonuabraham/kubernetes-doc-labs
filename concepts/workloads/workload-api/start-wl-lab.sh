#!/usr/bin/env bash
# Start the "wl-lab" minikube profile used by the Workload API / PodGroup /
# CompositePodGroup / scheduling-group / gang-scheduling labs.
# The APIs are beta/alpha and OFF by default in v1.37, so we enable:
#   feature gates : GenericWorkload, WorkloadWithJob, CompositePodGroup,
#                   TopologyAwareWorkloadScheduling, PodGroupPreemptionPolicy,
#                   DRAWorkloadResourceClaims
#   API versions  : scheduling.k8s.io/v1beta1 (Workload, PodGroup)
#                   scheduling.k8s.io/v1alpha3 (CompositePodGroup, v1alpha3 Workload)
# Single node on purpose: a 2nd node may stay NotReady on hosts with
# fs.inotify.max_user_instances=128 (see concepts/architecture/README.md).
minikube start -p wl-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 \
  --feature-gates=GenericWorkload=true,WorkloadWithJob=true,CompositePodGroup=true,TopologyAwareWorkloadScheduling=true,PodGroupPreemptionPolicy=true,DRAWorkloadResourceClaims=true \
  --extra-config=apiserver.runtime-config=scheduling.k8s.io/v1alpha3=true,scheduling.k8s.io/v1beta1=true
kubectl api-resources --api-group=scheduling.k8s.io
echo "When done: minikube stop -p wl-lab (or delete) ; kubectl config use-context minikube"
