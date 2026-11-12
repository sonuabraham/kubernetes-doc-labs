#!/usr/bin/env bash
kubectl delete pdb quux-pdb never-ready-pdb -n default --ignore-not-found
kubectl delete pod quux never-ready -n default --ignore-not-found --grace-period=0 --force 2>/dev/null
true
