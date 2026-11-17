# NOT from the docs: the official Python client outside the cluster, using the same kubeconfig as kubectl.
from kubernetes import client, config
config.load_kube_config()                       # ~/.kube/config (or $KUBECONFIG), current context
print("server:", client.Configuration.get_default_copy().host)
for ns in client.CoreV1Api().list_namespace().items:
    print("namespace:", ns.metadata.name)
