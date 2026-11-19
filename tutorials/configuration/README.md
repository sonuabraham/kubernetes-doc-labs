# Configuration – Section Page

Based on: https://kubernetes.io/docs/tutorials/configuration/

> The docs section page has no body, only the list of pages. The labs:
>
> | Lab | What it shows |
> |---|---|
> | [updating-configuration-via-a-configmap](updating-configuration-via-a-configmap/) | ConfigMap updates through a volume (live), env vars (need a rollout), multi-container and sidecar Pods, immutable ConfigMaps |
> | [configure-redis-using-configmap](configure-redis-using-configmap/) | Redis config from a ConfigMap; the volume updates but Redis re-reads it only after a restart |
> | [pod-sidecar-containers](pod-sidecar-containers/) | Turn a helper container into a native sidecar (`initContainers` + `restartPolicy: Always`) |
> | [configure-persistent-volume-storage](configure-persistent-volume-storage/) | hostPath PersistentVolume → PVC → Pod |
