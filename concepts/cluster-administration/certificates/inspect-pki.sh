#!/usr/bin/env bash
# Read-only tour of the cluster PKI on the minikube node: every certificate's subject, issuer, expiry and SANs.
minikube ssh -- 'sudo sh -c "
for f in \$(find /var/lib/minikube/certs -name \"*.crt\" | sort) /var/lib/kubelet/pki/kubelet-client-current.pem /var/lib/kubelet/pki/kubelet.crt; do
  [ -f \$f ] || continue
  printf \"%-58s\" \$f
  openssl x509 -in \$f -noout -subject -issuer -enddate -ext subjectAltName 2>/dev/null | tr \"\n\" \" \" | sed \"s/X509v3 Subject Alternative Name://; s/  */ /g\" | cut -c1-230; echo
done"'
