#!/usr/bin/env bash
kubectl delete namespace pss-privileged pss-baseline pss-restricted --ignore-not-found
