#!/usr/bin/env bash
kubectl delete namespace ingressctl-demo --ignore-not-found
kubectl delete ingressclass toy --ignore-not-found
