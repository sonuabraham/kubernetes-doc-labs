# Kubernetes Tutorials – Hands-on Labs

Labs for every page under https://kubernetes.io/docs/tutorials/ — one folder per page, mirroring the docs URL slugs.
Docs source synced at website commit be58364903 (2026-11-19). YAML from the docs is kept **verbatim**; anything added is marked "not from the docs".

Status: ✅ lab written · ⬜ not yet

- ✅ [Hello Minikube](hello-minikube/)
- **Learn Kubernetes Basics** (`kubernetes-basics/`) – [section page](kubernetes-basics/)  ✅
  - **Create a Cluster** (`kubernetes-basics/create-cluster/`) – [section page](kubernetes-basics/create-cluster/)  ✅
    - ✅ [Using Minikube to Create a Cluster](kubernetes-basics/create-cluster/cluster-intro/)
  - **Deploy an App** (`kubernetes-basics/deploy-app/`) – [section page](kubernetes-basics/deploy-app/)  ✅
    - ✅ [Using kubectl to Create a Deployment](kubernetes-basics/deploy-app/deploy-intro/)
  - **Explore Your App** (`kubernetes-basics/explore/`) – [section page](kubernetes-basics/explore/)  ✅
    - ✅ [Viewing Pods and Nodes](kubernetes-basics/explore/explore-intro/)
  - **Expose Your App Publicly** (`kubernetes-basics/expose/`) – [section page](kubernetes-basics/expose/)  ✅
    - ✅ [Using a Service to Expose Your App](kubernetes-basics/expose/expose-intro/)
  - **Scale Your App** (`kubernetes-basics/scale/`) – [section page](kubernetes-basics/scale/)  ✅
    - ✅ [Running Multiple Instances of Your App](kubernetes-basics/scale/scale-intro/)
  - **Update Your App** (`kubernetes-basics/update/`) – [section page](kubernetes-basics/update/)  ✅
    - ✅ [Performing a Rolling Update](kubernetes-basics/update/update-intro/)
- **Configuration** (`configuration/`) – [section page](configuration/)  ✅
  - ✅ [Updating Configuration via a ConfigMap](configuration/updating-configuration-via-a-configmap/)
  - ✅ [Configuring Redis using a ConfigMap](configuration/configure-redis-using-configmap/)
  - ✅ [Adopting Sidecar Containers](configuration/pod-sidecar-containers/)
  - ✅ [Configure a Pod to Use a PersistentVolume for Storage](configuration/configure-persistent-volume-storage/)
- **Security** (`security/`) – [section page](security/)  ⬜
  - ✅ [Apply Pod Security Standards at the Cluster Level](security/cluster-level-pss/)
  - ✅ [Apply Pod Security Standards at the Namespace Level](security/ns-level-pss/)
  - ⬜ [Restrict a Container's Access to Resources with AppArmor](security/apparmor/)
  - ⬜ [Restrict a Container's Syscalls with seccomp](security/seccomp/)
- **Stateless Applications** (`stateless-application/`) – [section page](stateless-application/)  ⬜
  - ⬜ [Deploy a Release Using a Canary Deployment](stateless-application/canary-deployment/)
  - ⬜ [Exposing an External IP Address to Access an Application in a Cluster](stateless-application/expose-external-ip-address/)
  - ⬜ [Example: Deploying PHP Guestbook application with Redis](stateless-application/guestbook/)
- **Stateful Applications** (`stateful-application/`) – [section page](stateful-application/)  ⬜
  - ⬜ [StatefulSet Basics](stateful-application/basic-stateful-set/)
  - ⬜ [Example: Deploying WordPress and MySQL with Persistent Volumes](stateful-application/mysql-wordpress-persistent-volume/)
  - ⬜ [Example: Deploying Cassandra with a StatefulSet](stateful-application/cassandra/)
  - ⬜ [Running ZooKeeper, A Distributed System Coordinator](stateful-application/zookeeper/)
- **Cluster Management** (`cluster-management/`) – [section page](cluster-management/)  ⬜
  - ⬜ [Running Kubelet in Standalone Mode](cluster-management/kubelet-standalone/)
  - ⬜ [Configuring swap memory on Kubernetes nodes](cluster-management/provision-swap-memory/)
  - ⬜ [Use Pod-Level Resources with kubelet Resource Managers](cluster-management/use-pod-level-resource-managers/)
  - ⬜ [Install Drivers and Allocate Devices with DRA](cluster-management/install-use-dra/)
  - ⬜ [Explore Validating and Mutating Admission Policies](cluster-management/admission-policies/)
  - ⬜ [Namespaces Walkthrough](cluster-management/namespaces-walkthrough/)
- **Services** (`services/`) – [section page](services/)  ⬜
  - ⬜ [Connecting Applications with Services](services/connect-applications-service/)
  - ⬜ [Using Source IP](services/source-ip/)
  - ⬜ [Explore Termination Behavior for Pods And Their Endpoints](services/pods-and-endpoint-termination-flow/)
