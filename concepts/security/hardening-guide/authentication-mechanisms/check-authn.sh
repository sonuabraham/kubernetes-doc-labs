#!/usr/bin/env bash
# Which authentication mechanisms is this API server configured with? (read-only)
F=$(kubectl get pod -n kube-system -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[]')
f(){ v=$(echo "$F" | grep -E -- "^--$1=" | cut -d= -f2-); printf '  %-38s %s\n' "--$1" "${v:-(not set)}"; }
echo "X.509 client certs";        f client-ca-file
echo "Static token file";         f token-auth-file
echo "Bootstrap tokens";          f enable-bootstrap-token-auth
echo "ServiceAccount tokens";     f service-account-key-file; f service-account-issuer; f service-account-max-token-expiration
echo "OIDC";                      f oidc-issuer-url; f authentication-config
echo "Webhook token";             f authentication-token-webhook-config-file
echo "Authenticating proxy";      f requestheader-client-ca-file; f requestheader-allowed-names; f requestheader-username-headers; f requestheader-group-headers
echo "Anonymous";                 f anonymous-auth
