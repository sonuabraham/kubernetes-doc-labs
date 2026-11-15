#!/usr/bin/env bash
# Remove everything the GMSA lab created (all in the default namespace / cluster scope, as in the docs).
kubectl delete deploy with-creds other --ignore-not-found
kubectl delete sa other --ignore-not-found
kubectl delete rolebinding allow-default-svc-account-read-on-gmsa-WebApp1 --ignore-not-found
kubectl delete clusterrole webapp1-role --ignore-not-found
kubectl delete -f gmsa-webhooks-as-policies.yaml --ignore-not-found
kubectl delete -f gmsa-crd.yaml --ignore-not-found     # also deletes every GMSACredentialSpec
