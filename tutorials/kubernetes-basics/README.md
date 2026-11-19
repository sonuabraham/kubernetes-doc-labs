# Learn Kubernetes Basics – Section Page

Based on: https://kubernetes.io/docs/tutorials/kubernetes-basics/

> The page lists six modules that build on each other with one app (`kubernetes-bootcamp`, a small Node.js web server):
> deploy it, look at it, expose it, scale it, update it. Each module has a lab folder below. Run them **in order** on the default minikube;
> [cleanup.sh](cleanup.sh) removes everything at the end (it's the docs' final command from module 6).

| Module | Section page | Lab |
|---|---|---|
| 1. Create a Kubernetes cluster | [create-cluster](create-cluster/) | [cluster-intro](create-cluster/cluster-intro/) |
| 2. Deploy an app | [deploy-app](deploy-app/) | [deploy-intro](deploy-app/deploy-intro/) |
| 3. Explore your app | [explore](explore/) | [explore-intro](explore/explore-intro/) |
| 4. Expose your app publicly | [expose](expose/) | [expose-intro](expose/expose-intro/) |
| 5. Scale up your app | [scale](scale/) | [scale-intro](scale/scale-intro/) |
| 6. Update your app | [update](update/) | [update-intro](update/update-intro/) |

Images (checked 2026-11-19 with containerd 2.3): `gcr.io/google-samples/kubernetes-bootcamp:v1` and `docker.io/jocatalin/kubernetes-bootcamp:v2`
pull fine; `gcr.io/google-samples/kubernetes-bootcamp:v10` doesn't exist, on purpose (module 6's broken update).
