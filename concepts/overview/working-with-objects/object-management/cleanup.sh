#!/usr/bin/env bash
# Usage: ./cleanup.sh  -> delete the objmgmt-demo namespace; restore configs/ edits with git or by hand
kubectl delete namespace objmgmt-demo --ignore-not-found
