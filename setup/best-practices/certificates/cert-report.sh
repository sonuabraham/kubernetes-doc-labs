#!/usr/bin/env bash
# NOT from the docs – print what a kubeadm control-plane node really has, to compare with the page's tables.
# Run as root on the node:  ../../production-environment/tools/kubeadm/machines.sh x cp1 "$(cat cert-report.sh)"
cd /etc/kubernetes/pki || exit 1
row() { # file
  local s i u n
  s=$(openssl x509 -in "$1" -noout -subject -nameopt compat | sed 's/^subject=//')
  i=$(openssl x509 -in "$1" -noout -issuer -nameopt compat | sed 's/^issuer=//')
  u=$(openssl x509 -in "$1" -noout -ext extendedKeyUsage 2>/dev/null | tail -1 | sed 's/^ *//; s/TLS Web //g; s/ Authentication//g')
  n=$(openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null | tail -1 | sed 's/^ *//; s/DNS://g; s/IP Address://g')
  printf '%-32s | %-48s | %-22s | %-14s | %s\n' "$1" "$s" "${i#CN=}" "${u:-CA}" "$n"
}
printf '%-32s | %-48s | %-22s | %-14s | %s\n' FILE SUBJECT "ISSUER(CN)" USAGE SANs
for f in $(find . -name '*.crt' | sed 's|^\./||' | sort); do row "$f"; done
echo; echo "keys without certs: $(ls sa.key sa.pub 2>/dev/null | tr '\n' ' ')"
echo; echo "== kubeconfigs in /etc/kubernetes (user name → client cert subject)"
for k in /etc/kubernetes/*.conf; do
  u=$(grep -A0 -m1 '^- name:' "$k" | awk '{print $3}')
  d=$(grep -m1 'client-certificate-data:' "$k" | awk '{print $2}')
  if [ -n "$d" ]; then s=$(echo "$d" | base64 -d | openssl x509 -noout -subject -nameopt compat | sed 's/^subject=//'); else s="(file: $(grep -m1 'client-certificate:' "$k" | awk '{print $2}'))"; fi
  printf '%-45s user=%-35s %s\n' "$k" "$u" "$s"
done
echo; echo "== kubelet serving cert"; openssl x509 -in /var/lib/kubelet/pki/kubelet.crt -noout -subject -issuer -nameopt compat
echo; echo "== flags that point at the files"
grep -hoE -- '--(etcd-cafile|etcd-certfile|etcd-keyfile|client-ca-file|tls-cert-file|tls-private-key-file|kubelet-client-certificate|kubelet-client-key|requestheader-client-ca-file|proxy-client-cert-file|proxy-client-key-file|service-account-key-file|service-account-private-key-file|service-account-signing-key-file|cluster-signing-cert-file|cluster-signing-key-file|root-ca-file|trusted-ca-file|peer-trusted-ca-file|cert-file|key-file|peer-cert-file|peer-key-file)=[^ ]*' /etc/kubernetes/manifests/*.yaml | sort -u
