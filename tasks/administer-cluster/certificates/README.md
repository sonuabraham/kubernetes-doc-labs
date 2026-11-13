# Generate Certificates Manually – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/certificates/

> This lab builds the API-server certificate set (CA + serving cert/key) with all three tools on the page: **easyrsa**, **openssl** and **cfssl**. Every result is verified and then used in a **real TLS handshake**. [tls-test.sh](tls-test.sh) serves the cert with `openssl s_server`, a stand-in for `kube-apiserver --tls-cert-file/--tls-private-key-file`, and connects with curl (the OpenSSL verifier) and kubectl (the Go verifier). The CA is then distributed into a throwaway container's trust store.
>
> The docs' config templates are **verbatim** in [templates/](templates/) (`csr.conf`, `ca-config.json`, `ca-csr.json`, `server-csr.json`, with their `<placeholders>`). [fill-templates.sh](fill-templates.sh) copies them to `work/` (gitignored) with the minikube values filled in:
> - `MASTER_IP` = `minikube ip`
> - `MASTER_CLUSTER_IP` = the `kubernetes` Service ClusterIP, 10.96.0.1

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **What the API server needs** | `--client-ca-file` (CA that signs *client* certs), `--tls-cert-file` + `--tls-private-key-file` (its serving cert). |
| **SANs** | Every name or IP clients dial: the node IP, the **first Service IP** (`kubernetes.default` → 10.96.0.1 for in-cluster clients), and `kubernetes`, `kubernetes.default`, `…svc`, `…svc.cluster`, `…svc.cluster.local`. Add `127.0.0.1` if anything connects locally. |
| **easyrsa** | Wraps openssl around a `pki/` directory: `build-ca`, then `build-server-full`. Adds `digitalSignature` and only `serverAuth`. |
| **openssl** | Fully manual: key → self-signed CA → CSR from `csr.conf` → sign with `-extensions v3_ext`. |
| **cfssl** | JSON-driven: `gencert -initca` for the CA, then `gencert -profile=kubernetes` for the server. Expiry comes from `ca-config.json` (8760h = 1 year). |
| **Trust** | A self-signed CA is unknown to clients. Pass it explicitly (`--cacert`, `certificate-authority`), or install it system-wide (`update-ca-certificates`). |
| **Certificates API** | Inside a running cluster, prefer `certificates.k8s.io` CSRs (see Managing TLS in a cluster). |

---

## Step 0
```bash
cd tasks/administer-cluster/certificates
./fill-templates.sh
#   MASTER_IP=192.168.58.2 MASTER_CLUSTER_IP=10.96.0.1 -> ca-config.json ca-csr.json csr.conf server-csr.json
export MASTER_IP=$(minikube ip) MASTER_CLUSTER_IP=10.96.0.1
```

## Lab 1 – openssl
```bash
mkdir -p work/openssl && cd work/openssl && cp ../csr.conf .
openssl genrsa -out ca.key 2048
openssl req -x509 -new -noenc -key ca.key -subj "/CN=${MASTER_IP}" -days 10000 -out ca.crt
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -config csr.conf
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out server.crt -days 10000 \
    -extensions v3_ext -extfile csr.conf -sha256
#   Certificate request self-signature ok
#   subject=C=AU, ST=NSW, L=Sydney, O=Lab, OU=k8s-docs, CN=192.168.58.2
openssl req  -noout -text -in ./server.csr | grep -A1 Alternative
openssl x509 -noout -text -in ./server.crt | grep -A1 -E "Issuer|Not After|Key Usage|Alternative"
#   Issuer: CN=192.168.58.2              Not After : Mar 31 2054   (10000 days)
#   X509v3 Key Usage: Key Encipherment, Data Encipherment
#   X509v3 Extended Key Usage: TLS Web Server Authentication, TLS Web Client Authentication
#   X509v3 Subject Alternative Name: DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc,
#       DNS:kubernetes.default.svc.cluster, DNS:kubernetes.default.svc.cluster.local, IP Address:192.168.58.2, IP Address:10.96.0.1
openssl verify -CAfile ca.crt server.crt                  # server.crt: OK
cd ../..
```

## Lab 2 – easyrsa (the Kubernetes-patched copy)
```bash
mkdir -p work/easyrsa && cd work/easyrsa
curl -LO https://dl.k8s.io/easy-rsa/easy-rsa.tar.gz
tar xzf easy-rsa.tar.gz
cd easy-rsa-master/easyrsa3
./easyrsa init-pki
./easyrsa --batch "--req-cn=${MASTER_IP}@`date +%s`" build-ca nopass
./easyrsa --subject-alt-name="IP:${MASTER_IP},"\
"IP:${MASTER_CLUSTER_IP},"\
"DNS:kubernetes,"\
"DNS:kubernetes.default,"\
"DNS:kubernetes.default.svc,"\
"DNS:kubernetes.default.svc.cluster,"\
"DNS:kubernetes.default.svc.cluster.local" \
--days=10000 \
build-server-full server nopass
#   Write out database with 1 new entries   Database updated
openssl x509 -in pki/issued/server.crt -noout -subject -issuer -ext subjectAltName,keyUsage,extendedKeyUsage
#   subject=CN=server     issuer=CN=192.168.58.2@1794564894
#   X509v3 Extended Key Usage: TLS Web Server Authentication
#   X509v3 Key Usage: Digital Signature, Key Encipherment
#   X509v3 Subject Alternative Name: IP Address:192.168.58.2, IP Address:10.96.0.1, DNS:kubernetes, ...
openssl verify -CAfile pki/ca.crt pki/issued/server.crt   # OK
cd ../../../..
```
The page's "copy `pki/ca.crt`, `pki/issued/server.crt`, `pki/private/server.key` to your directory" step means those three files.

## Lab 3 – cfssl
```bash
mkdir -p work/cfssl && cd work/cfssl
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.5.0/cfssl_1.5.0_linux_amd64 -o cfssl
chmod +x cfssl
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.5.0/cfssljson_1.5.0_linux_amd64 -o cfssljson
chmod +x cfssljson
curl -L https://github.com/cloudflare/cfssl/releases/download/v1.5.0/cfssl-certinfo_1.5.0_linux_amd64 -o cfssl-certinfo
chmod +x cfssl-certinfo
mkdir cert
cd cert
../cfssl print-defaults config > config.json
../cfssl print-defaults csr > csr.json
cp ../../ca-config.json ../../ca-csr.json ../../server-csr.json .        # the filled-in docs JSON
../cfssl gencert -initca ca-csr.json | ../cfssljson -bare ca                # -> ca.pem ca-key.pem ca.csr
../cfssl gencert -ca=ca.pem -ca-key=ca-key.pem \
     --config=ca-config.json -profile=kubernetes \
     server-csr.json | ../cfssljson -bare server                             # -> server.pem server-key.pem
../cfssl-certinfo -cert server.pem | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["sans"],d["not_after"])'
#   ['kubernetes', ..., 'kubernetes.default.svc.cluster.local', '127.0.0.1', '192.168.58.2', '10.96.0.1'] 2027-11-13T...   <- 8760h
openssl verify -CAfile ca.pem server.pem
#   error 18 at 0 depth lookup: self-signed certificate      <- !!
openssl x509 -in ca.pem -noout -subject; openssl x509 -in server.pem -noout -subject
#   subject=C=AU, ST=NSW, L=Sydney, O=Lab, OU=k8s-docs, CN=kubernetes
#   subject=C=AU, ST=NSW, L=Sydney, O=Lab, OU=k8s-docs, CN=kubernetes     <- identical subject to its issuer
cd ../../..
```
The docs' `ca-csr.json` and `server-csr.json` share the same `CN: kubernetes`. If you fill the `names` the same way, which is natural, the server cert's **subject equals its issuer**. OpenSSL then treats it as a self-signed leaf and fails verification. Go doesn't care (see Lab 4). The fix is a distinct CA name:
```bash
cd work/cfssl && mkdir -p fixed && cd fixed
sed 's/"CN": "kubernetes"/"CN": "kubernetes-ca"/' ../cert/ca-csr.json > ca-csr.json; cp ../cert/ca-config.json ../cert/server-csr.json .
../cfssl gencert -initca ca-csr.json | ../cfssljson -bare ca
../cfssl gencert -ca=ca.pem -ca-key=ca-key.pem --config=ca-config.json -profile=kubernetes server-csr.json | ../cfssljson -bare server
openssl verify -CAfile ca.pem server.pem          # server.pem: OK
cd ../../..
```

## Lab 4 – Use them: TLS handshakes
```bash
./tls-test.sh work/openssl/server.crt work/openssl/server.key work/openssl/ca.crt
#   curl    https://kubernetes.default.svc: 200
#   kubectl https://127.0.0.1:              x509: certificate is valid for 192.168.58.2, 10.96.0.1, not 127.0.0.1
E=work/easyrsa/easy-rsa-master/easyrsa3/pki
./tls-test.sh $E/issued/server.crt $E/private/server.key $E/ca.crt
#   curl 200 ; kubectl: not 127.0.0.1                    (same SAN list as openssl)
./tls-test.sh work/cfssl/cert/server.pem work/cfssl/cert/server-key.pem work/cfssl/cert/ca.pem
#   curl    https://kubernetes.default.svc: curl: (60) SSL certificate OpenSSL verify result: self-signed certificate (18)
#   kubectl https://127.0.0.1:              TLS OK (got the test page)     <- Go accepts it; cfssl's hosts include 127.0.0.1
./tls-test.sh work/cfssl/fixed/server.pem work/cfssl/fixed/server-key.pem work/cfssl/fixed/ca.pem
#   curl 200 ; kubectl TLS OK
```
Also try `curl --resolve other.example:18443:127.0.0.1 https://other.example:18443/`. It fails with *no alternative certificate subject name matches target hostname*.

## Lab 5 – Distributing the self-signed CA
This is the page's two commands, run in a throwaway container from the local kicbase image (Debian), so your host's trust store isn't touched:
```bash
cd work/openssl
docker run --rm -v "$PWD":/w:ro --entrypoint bash gcr.io/k8s-minikube/kicbase:v0.0.51 -c '
  cd /w; openssl s_server -accept 18443 -cert server.crt -key server.key -www -quiet >/dev/null 2>&1 & sleep 1
  curl -sS --resolve kubernetes:18443:127.0.0.1 https://kubernetes:18443/ -o /dev/null -w "%{http_code}\n"
  cp ca.crt /usr/local/share/ca-certificates/kubernetes.crt
  update-ca-certificates
  curl -sS --resolve kubernetes:18443:127.0.0.1 https://kubernetes:18443/ -o /dev/null -w "%{http_code}\n"'
#   curl: (60) SSL certificate problem: unable to get local issuer certificate     <- no --cacert, not trusted
#   Updating certificates in /etc/ssl/certs...
#   1 added, 0 removed; done.
#   200                                                                              <- trusted system-wide now
cd ../..
```

---

## Useful commands
```bash
openssl x509 -in c.crt -noout -subject -issuer -dates -ext subjectAltName,keyUsage,extendedKeyUsage
openssl verify -CAfile ca.crt server.crt
openssl s_client -connect <host>:6443 -servername kubernetes.default.svc </dev/null | openssl x509 -noout -ext subjectAltName
cfssl-certinfo -cert server.pem
```

## Cleanup
```bash
rm -rf work          # all generated keys, certs and downloaded tools (gitignored)
```
