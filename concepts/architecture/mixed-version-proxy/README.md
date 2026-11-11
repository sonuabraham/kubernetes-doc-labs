# Mixed Version Proxy – Hands-on Lab

Based on: https://kubernetes.io/docs/concepts/architecture/mixed-version-proxy/

> Cluster: the **`arch-lab`** profile (see [../README.md](../README.md)). The feature only means something with **two or more API servers**, and minikube runs one. [setup-peer-apiservers.sh](setup-peer-apiservers.sh) builds a second one (**B**) as a static pod on the worker. It shares etcd with the original (**A**) and serves **every** alpha/beta API (`--runtime-config=api/all=true`), the way a newer API server would during an upgrade. **Lab-only.** [teardown-peer-apiservers.sh](teardown-peer-apiservers.sh) undoes it.

## Key ideas (read first)

| Concept | Meaning |
|---|---|
| **The problem** | During a long upgrade, API servers of different versions run side by side. A request for an API that only the newer server knows can land on the older one, giving a surprise **404**. Controllers that read discovery see an **incomplete** list. |
| **Feature gate** | `UnknownVersionInteroperabilityProxy` (beta). Required flags: `--peer-ca-file`, `--proxy-client-cert-file`/`--proxy-client-key-file`, `--requestheader-client-ca-file`, `--requestheader-allowed-names`. Optional: `--peer-advertise-ip`/`--peer-advertise-port` (defaults to `--advertise-address`). |
| **Peer-aggregated discovery** | `/apis` aggregated discovery lists resources served by **any** API server in the cluster. Add `;profile=nopeer` to the Accept header to get only the local server's view. Not available for legacy unaggregated discovery. |
| **Mixed version proxy** | If the handling server doesn't serve the requested group/version/resource (too old, or the API is turned off), it finds a peer that does (from the peers' **nopeer** discovery) and **proxies** the request there. No peer → 404. Peer chosen but not responding → 503. |
| **Peer identity** | Peers find each other through the **API server identity Leases** (`apiserver-<hash(hostname)>`, see `../leases`). Proxied requests are authenticated with the aggregator's proxy client cert. Peer serving certs are verified against `--peer-ca-file`. |

## The demo app
| | A (original) | B (added by the script) |
|---|---|---|
| Node / address | `arch-lab` 192.168.67.2:8443 | `arch-lab-m02` 192.168.67.3:8443 |
| APIs | defaults (GA only) | `--runtime-config=api/all=true` (+ alpha/beta) |
| Feature flags | `UnknownVersionInteroperabilityProxy=true`, `--peer-ca-file` | same |
| Serving cert | minikube's | new, SAN 192.168.67.3, signed by the cluster CA |

The script copies the certs and A's manifest to the worker, generates B's serving cert with openssl, writes `/etc/kubernetes/manifests/kube-apiserver-peer.yaml`, and adds the two flags to A, which restarts it.

---

## Step 1 – Build two API servers
```bash
cd concepts/architecture/mixed-version-proxy
kubectl config use-context arch-lab
./setup-peer-apiservers.sh
sleep 30
kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver -L kubernetes.io/hostname
#   apiserver-ioctspdw6inas6ya5ooxupcz2a   ...   arch-lab        <- A
#   apiserver-zizihgsxnf7dpc3z2sd6lkwkji   ...   arch-lab-m02    <- B (its own identity lease)
```
Talk to each server directly with your minikube client certificate:
```bash
c(){ curl -s --cacert ~/.minikube/ca.crt --cert ~/.minikube/profiles/arch-lab/client.crt --key ~/.minikube/profiles/arch-lab/client.key "$@"; }
A=https://192.168.67.2:8443 ; B=https://192.168.67.3:8443
H='Accept: application/json;g=apidiscovery.k8s.io;v=v2;as=APIGroupDiscoveryList'
```

## Lab 1 – Peer-aggregated discovery
```bash
echo "A local only : $(c -H "$H;profile=nopeer" $A/apis | jq '[.items[].versions[]] | length')"
echo "B local only : $(c -H "$H;profile=nopeer" $B/apis | jq '[.items[].versions[]] | length')"
echo "A aggregated : $(c -H "$H"               $A/apis | jq '[.items[].versions[]] | length')"
```
Expected:
```
A local only : 22
B local only : 32
A aggregated : 32      <- A advertises what B serves too: the "holistic view"
```
Which group-versions only B has:
```bash
comm -13 <(c -H "$H;profile=nopeer" $A/apis | jq -r '.items[] | .metadata.name as $g | .versions[] | "\($g)/\(.version)"' | sort) \
         <(c -H "$H;profile=nopeer" $B/apis | jq -r '.items[] | .metadata.name as $g | .versions[] | "\($g)/\(.version)"' | sort)
#   admissionregistration.k8s.io/v1alpha1  admissionregistration.k8s.io/v1beta1  certificates.k8s.io/v1beta1
#   coordination.k8s.io/v1alpha2  coordination.k8s.io/v1beta1  internal.apiserver.k8s.io/v1alpha1
#   resource.k8s.io/v1alpha3  resource.k8s.io/v1beta1  resource.k8s.io/v1beta2  storagemigration.k8s.io/v1beta1
```

## Lab 2 – Mixed version proxying
Ask **A** for an API that only **B** serves:
```bash
c -o /dev/null -w 'A: %{http_code}\n' $A/apis/coordination.k8s.io/v1alpha2/leasecandidates      # A: 200   <- proxied to B
c $A/apis/coordination.k8s.io/v1alpha2/leasecandidates | jq -c '{kind, apiVersion}'
#   {"kind":"LeaseCandidateList","apiVersion":"coordination.k8s.io/v1alpha2"}
c -o /dev/null -w 'A: %{http_code}\n' $A/apis/coordination.k8s.io/v9/leases                       # A: 404   <- no peer serves it
kubectl get leasecandidates.v1alpha2.coordination.k8s.io -A     # kubectl, via A, works the same way
```
Without the feature gate on A, the first request would be a **404**. That's exactly the upgrade-time surprise the feature prevents.

## Lab 3 – When the peer goes away
```bash
minikube ssh -p arch-lab -n arch-lab-m02 -- "sudo mv /etc/kubernetes/manifests/kube-apiserver-peer.yaml /tmp/"
sleep 20
c -o /dev/null -w 'A: %{http_code}\n' $A/apis/coordination.k8s.io/v1alpha2/leasecandidates
c $A/apis/coordination.k8s.io/v1alpha2/leasecandidates | jq -r .message
minikube ssh -p arch-lab -n arch-lab-m02 -- "sudo mv /tmp/kube-apiserver-peer.yaml /etc/kubernetes/manifests/"
```
The docs describe **503** for "peer selected but not responding". In this run, 20s after B stopped, A answered **404** "the server could not find the requested resource": A had already dropped B from its list of peers that serve the API. Expect a 503 only in the short window when A still believes the peer is there.

## Lab 4 – What carries the trust
```bash
kubectl get pod -n kube-system kube-apiserver-arch-lab -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep -E 'peer|proxy-client|requestheader-(client|allowed)|feature'
#   --feature-gates=UnknownVersionInteroperabilityProxy=true
#   --peer-ca-file=/var/lib/minikube/certs/ca.crt                       <- A verifies B's serving cert
#   --proxy-client-cert-file=.../front-proxy-client.crt                 <- A's identity when proxying
#   --requestheader-client-ca-file=.../front-proxy-ca.crt               <- B checks A's proxy cert against this
#   --requestheader-allowed-names=front-proxy-client
minikube ssh -p arch-lab -n arch-lab-m02 -- "sudo openssl x509 -in /var/lib/minikube/peer-certs/peer-apiserver.crt -noout -ext subjectAltName"
#   IP Address:192.168.67.3, ...                                        <- without this SAN, A's TLS check of B fails
```

---

## Useful commands
```bash
kubectl -n kube-system get lease -l apiserver.kubernetes.io/identity=kube-apiserver
curl ... -H 'Accept: application/json;g=apidiscovery.k8s.io;v=v2;as=APIGroupDiscoveryList;profile=nopeer' <server>/apis
kubectl get --raw /apis | jq -r '.groups[].preferredVersion.groupVersion'
```

## Cleanup
```bash
./teardown-peer-apiservers.sh      # remove B, take the feature flags off A (A restarts)
```
