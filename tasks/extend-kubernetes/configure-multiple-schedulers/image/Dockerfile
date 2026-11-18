# The docs' Dockerfile is:
#   FROM busybox
#   ADD ./_output/local/bin/linux/amd64/kube-scheduler /usr/local/bin/kube-scheduler
# Instead of building Kubernetes from source (`make`, ~30 min), this copies the same binary from the official
# kube-scheduler image of the cluster's version. NOT from the docs.
FROM registry.k8s.io/kube-scheduler:v1.37.0 AS upstream
FROM busybox:1.36
COPY --from=upstream /usr/local/bin/kube-scheduler /usr/local/bin/kube-scheduler
