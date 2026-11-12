#!/usr/bin/env bash
# Remove the demo objects. kubeadm-level changes: recreate the profile (see README Cleanup).
kubectl --context kubeadm-lab delete ns reconfigure-demo --ignore-not-found
kubectl --context kubeadm-lab label no kubeadm-lab lab.example.com/rack-
