# Toy device plugin + PodResources client. Build into the minikube node:  minikube image build -t toy-foo-plugin:1 toy-plugin/
FROM python:3.12-slim
RUN pip install --no-cache-dir grpcio==1.66.1 grpcio-tools==1.66.1
WORKDIR /app
COPY deviceplugin.proto podresources.proto plugin.py podresources.py ./
RUN python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. deviceplugin.proto podresources.proto
CMD ["python", "-u", "plugin.py"]
