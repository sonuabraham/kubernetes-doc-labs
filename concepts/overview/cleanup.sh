#!/usr/bin/env bash
kubectl delete namespace overview-demo --ignore-not-found
kubectl delete crd coupons.shop.example.com --ignore-not-found
