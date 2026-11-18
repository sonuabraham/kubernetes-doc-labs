#!/usr/bin/env bash
# Remove everything this lab created. Delete the CRD before the webhook (objects may need conversion while being deleted).
kubectl delete storageversionmigration crontabs-migration --ignore-not-found
kubectl delete crd crontabs.example.com widgets.prio.example.com --ignore-not-found
kubectl delete -f "$(dirname "$0")/webhook-deployment.yaml" --ignore-not-found
kubectl delete secret conversion-webhook-tls --ignore-not-found
kubectl delete configmap conversion-webhook-code --ignore-not-found
