# Hardening Guide – Hands-on Labs

Based on: https://kubernetes.io/docs/concepts/security/hardening-guide/

| Page | Lab shows |
|---|---|
| [authentication-mechanisms](authentication-mechanisms/) | which authenticators are on; X.509 certs can't be revoked; bootstrap tokens are credentials |
| [dynamic-resource-allocation](dynamic-resource-allocation/) | `resourceclaims/binding` vs `resourceclaims/driver` with `associated-node:`/`arbitrary-node:` verbs, per ServiceAccount |
| [scheduler](scheduler/) | scheduler flags and debug endpoints (profiling on by default); a second scheduler with filters disabled binds anything, and the kubelet backstops it |
