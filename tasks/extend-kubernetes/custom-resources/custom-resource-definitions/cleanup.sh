#!/usr/bin/env bash
# Remove everything this lab created (deleting a CRD deletes all its objects).
kubectl delete crd crontabs.stable.example.com shirts.stable.example.com frags.lab.example.com limits.lab.example.com --ignore-not-found
