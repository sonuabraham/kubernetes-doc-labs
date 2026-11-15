#!/usr/bin/env bash
kubectl delete pod linux-host-demo hostprocess-demo --ignore-not-found --now
kubectl delete ns hpc-privileged hpc-baseline hpc-restricted --ignore-not-found
