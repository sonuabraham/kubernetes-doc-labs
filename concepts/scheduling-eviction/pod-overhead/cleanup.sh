#!/usr/bin/env bash
kubectl delete namespace po-demo --ignore-not-found
kubectl delete runtimeclass kata-fc runc-overhead --ignore-not-found
