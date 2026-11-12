#!/usr/bin/env bash
kubectl delete namespace psp-migrated --ignore-not-found
kubectl delete validatingadmissionpolicybinding require-readonly-rootfs --ignore-not-found
kubectl delete validatingadmissionpolicy require-readonly-rootfs --ignore-not-found
