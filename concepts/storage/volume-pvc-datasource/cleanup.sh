#!/usr/bin/env bash
kubectl delete namespace myns otherns --ignore-not-found
kubectl delete storageclass cloning --ignore-not-found
