#!/usr/bin/env bash
kubectl delete namespace proj-demo proj-demo2 --ignore-not-found
kubectl delete pod podcertificate-pod -n default --ignore-not-found
kubectl delete podcertificaterequests -n default --all --ignore-not-found
kubectl delete clustertrustbundle example example.com:mysigner:live-roots --ignore-not-found
rm -rf "$(dirname "$0")/.toy-ca"
