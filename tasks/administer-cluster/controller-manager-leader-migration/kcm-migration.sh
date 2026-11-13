#!/usr/bin/env bash
# ./kcm-migration.sh on <config.yaml>   kube-controller-manager = "version N": leader election ON, Leader Migration ON,
#                                       config copied to /etc/leadermigration.conf and mounted at the same path.
# ./kcm-migration.sh off                "version N+1" KCM: Leader Migration flags + mount removed (it MUST NOT take part).
# Edits the static Pod manifest on the lm-lab node; the original is kept in /root.        (P=<profile>, default lm-lab)
P=${P:-lm-lab}; D=$(cd "$(dirname "$0")/.." && pwd); MODE=$1
[ "$MODE" = on ] && minikube -p "$P" cp "${2:?config file}" /etc/leadermigration.conf >/dev/null
P=$P "$D/kubeadm/node.sh" "M=/etc/kubernetes/manifests/kube-controller-manager.yaml
  [ -f /root/kcm.orig.yaml ] || cp \$M /root/kcm.orig.yaml
  cp /root/kcm.orig.yaml /tmp/kcm.yaml
  sed -i \"/--leader-elect=false/d\" /tmp/kcm.yaml
  if [ \"$MODE\" = on ]; then
    sed -i \"s|^    - kube-controller-manager\$|&\n    - --enable-leader-migration\n    - --leader-migration-config=/etc/leadermigration.conf|\" /tmp/kcm.yaml
    sed -i \"s|^    volumeMounts:\$|&\n    - name: leadermigration\n      mountPath: /etc/leadermigration.conf\n      readOnly: true|\" /tmp/kcm.yaml
    sed -i \"s|^  volumes:\$|&\n  - name: leadermigration\n    hostPath:\n      path: /etc/leadermigration.conf\n      type: File|\" /tmp/kcm.yaml
  fi
  cp /tmp/kcm.yaml \$M
  grep -nE \"leader|leadermigration\" \$M"
