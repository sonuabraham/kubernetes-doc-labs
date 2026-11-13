#!/usr/bin/env bash
kubectl delete ns example --ignore-not-found
kubectl delete priorityclass placeholder --ignore-not-found
