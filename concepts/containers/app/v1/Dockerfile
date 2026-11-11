# A tiny "application" image, version v1. Each version is a SEPARATE, immutable image.
FROM busybox:1.36
ENV APP_VERSION=v1
CMD ["sh", "-c", "while true; do echo \"hello from app $APP_VERSION on $(hostname)\"; sleep 5; done"]
