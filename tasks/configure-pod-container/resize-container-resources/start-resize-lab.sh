#!/usr/bin/env bash
# Throwaway single-node profile "resize-lab" with the two ALPHA resize gates (both off by default in v1.37):
#   InPlacePodVerticalScalingMemoryBackedVolumes  - resize emptyDir{medium: Memory}.sizeLimit via /resize
#   InPlacePodVerticalScalingSchedulerPreemption  - scheduler preempts lower-priority Pods for a Deferred resize
# 2 CPUs on purpose, so a Deferred resize is easy to provoke.
minikube start -p resize-lab --memory 2200 --cpus 2 --kubernetes-version v1.37.0 \
  --feature-gates=InPlacePodVerticalScalingMemoryBackedVolumes=true,InPlacePodVerticalScalingSchedulerPreemption=true
kubectl --context resize-lab get --raw /metrics | grep -E 'kubernetes_feature_enabled\{name="InPlacePodVerticalScaling(MemoryBacked|Scheduler)'
echo "When done: minikube delete -p resize-lab ; kubectl config use-context minikube"
