# Verify Signed Kubernetes Artifacts – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/administer-cluster/verify-signed-artifacts/

> All of the page's verifications are run for real against the published v1.37 artifacts. The docs' commands are unchanged. `cosign` isn't installed on this host, so [cosign.sh](cosign.sh) defines a `cosign` shell function that runs Sigstore's official image (`gcr.io/projectsigstore/cosign:v2.4.1`) with the current directory mounted. Everything is downloaded into `dl/` (gitignored).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| **Keyless signing** | Release artifacts are signed with **cosign** using short-lived certificates from Sigstore's Fulcio CA. Each signature is recorded in the Rekor transparency log. There's no long-lived public key to manage. |
| **What you check** | The signature matches the bytes, the certificate chains to Sigstore, and its **identity** is the release robot: `--certificate-identity` + `--certificate-oidc-issuer` (required since cosign 2.0). |
| **Identities** | Binaries and the SBOM: `krel-staging@k8s-releng-prod.iam.gserviceaccount.com`. Images: `krel-trust@k8s-releng-prod.iam.gserviceaccount.com`. Issuer `https://accounts.google.com`. |
| **SBOM** | `sbom.k8s.io/<version>/release` (SPDX), with `.sha512` / `.sha256` / `.sig` / `.cert` next to it. It also lists every signed image. |
| **After verifying** | Pin images by **digest** (`image@sha256:...`), and/or enforce signatures at admission time (sigstore policy-controller). |

---

## Step 0
```bash
cd tasks/administer-cluster/verify-signed-artifacts
source ./cosign.sh && cosign version | grep GitVersion        # v2.4.1
mkdir -p dl && cd dl
```

## Lab 1 – Verify a binary (kubectl v1.37.0)
```bash
URL=https://dl.k8s.io/release/v1.37.0/bin/linux/amd64
BINARY=kubectl
FILES=(
    "$BINARY"
    "$BINARY.sig"
    "$BINARY.cert"
)
for FILE in "${FILES[@]}"; do
    curl -sSfL --retry 3 --retry-delay 3 "$URL/$FILE" -o "$FILE"
done
cosign verify-blob "$BINARY" \
  --signature "$BINARY".sig \
  --certificate "$BINARY".cert \
  --certificate-identity krel-staging@k8s-releng-prod.iam.gserviceaccount.com \
  --certificate-oidc-issuer https://accounts.google.com
#   Verified OK
```
Two ways to fail on purpose:
```bash
cp kubectl kubectl-tampered; printf 'x' >> kubectl-tampered          # one extra byte
cosign verify-blob kubectl-tampered --signature kubectl.sig --certificate kubectl.cert --certificate-identity krel-staging@k8s-releng-prod.iam.gserviceaccount.com --certificate-oidc-issuer https://accounts.google.com
#   error during command execution: searching log query: [POST /api/v1/log/entries/retrieve][400] ... verifying ...
cosign verify-blob kubectl --signature kubectl.sig --certificate kubectl.cert --certificate-identity someone-else@example.com --certificate-oidc-issuer https://accounts.google.com
#   error ...: none of the expected identities matched what was in the certificate, got subjects [krel-staging@k8s-releng-prod.iam.gserviceaccount.com] ...
```

## Lab 2 – Verify an image
```bash
cosign verify registry.k8s.io/kube-apiserver-amd64:v1.37.0 \
  --certificate-identity krel-trust@k8s-releng-prod.iam.gserviceaccount.com \
  --certificate-oidc-issuer https://accounts.google.com \
  | jq .
#   (stderr) The following checks were performed on each of these signatures:
#     - The cosign claims were validated
#     - Existence of the claims in the transparency log was verified offline
#     - The code-signing certificate was verified using trusted certificate authority certificates
#   [ { "critical": { "identity": {"docker-reference": "registry.k8s.io/kube-apiserver-amd64"},
#                     "image": {"docker-manifest-digest": "sha256:83f25d9626d2860003425ad0e31b4d3c73738b2ee16505fca9645d6443b719da"}, ... },
#       "optional": { "Issuer": "https://accounts.google.com", "Subject": "krel-trust@k8s-releng-prod.iam.gserviceaccount.com", ... } } ]
```
Pin what you verified by digest, e.g. `registry.k8s.io/kube-apiserver-amd64@sha256:83f25d9626d2860003425ad0e31b4d3c73738b2ee16505fca9645d6443b719da`.

## Lab 3 – Verify all control-plane images of the latest stable release (the docs' loop)
```bash
curl -Ls "https://sbom.k8s.io/$(curl -Ls https://dl.k8s.io/release/stable.txt)/release" \
  | grep "SPDXID: SPDXRef-Package-registry.k8s.io" \
  | grep -v sha256 | cut -d- -f3- | sed 's/-/\//' | sed 's/-v1/:v1/' \
  | sort > images.txt
wc -l < images.txt          # 24   (stable.txt = v1.37.2)
head -3 images.txt          # registry.k8s.io/conformance-amd64:v1.37.2  ...-arm64  ...-ppc64le ...
input=images.txt
while IFS= read -r image
do
  cosign verify "$image" \
    --certificate-identity krel-trust@k8s-releng-prod.iam.gserviceaccount.com \
    --certificate-oidc-issuer https://accounts.google.com \
    | jq .
done < "$input"
#   (counted instead of printed: verified=24 failed=0)
```

## Lab 4 – Verify the SBOM
```bash
VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)        # v1.37.2
curl -Ls "https://sbom.k8s.io/$VERSION/release" -o "$VERSION.spdx"
echo "$(curl -Ls "https://sbom.k8s.io/$VERSION/release.sha512") $VERSION.spdx" | sha512sum --check      # v1.37.2.spdx: OK
echo "$(curl -Ls "https://sbom.k8s.io/$VERSION/release.sha256") $VERSION.spdx" | sha256sum --check      # v1.37.2.spdx: OK
curl -Ls "https://sbom.k8s.io/$VERSION/release.sig" -o "$VERSION.spdx.sig"
curl -Ls "https://sbom.k8s.io/$VERSION/release.cert" -o "$VERSION.spdx.cert"
cosign verify-blob \
    --certificate "$VERSION.spdx.cert" \
    --signature "$VERSION.spdx.sig" \
    --certificate-identity krel-staging@k8s-releng-prod.iam.gserviceaccount.com \
    --certificate-oidc-issuer https://accounts.google.com \
    "$VERSION.spdx"
#   Verified OK
```

## Verifying at admission time
For your own (non-control-plane) images, the page points to the **sigstore policy-controller** (Helm chart `sigstore/policy-controller`). It's an admission webhook that rejects Pods whose images don't match a `ClusterImagePolicy` (e.g. "signed by identity X"). That needs a third-party install and isn't run here.

---

## Useful commands
```bash
cosign verify-blob <file> --signature <file>.sig --certificate <file>.cert --certificate-identity <id> --certificate-oidc-issuer <issuer>
cosign verify <image> --certificate-identity <id> --certificate-oidc-issuer <issuer>
cosign tree <image>                     # signatures/attestations attached to an image
```

## Cleanup
```bash
rm -rf dl                               # downloaded binaries, signatures, SBOM (gitignored)
```
