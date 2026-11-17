# Job with Pod-to-Pod Communication – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/job/job-with-pod-to-pod-communication/

> Runs on the default **minikube** cluster, `default` namespace. File: [example-job.yaml](example-job.yaml) (the docs' inline example, **verbatim**).
>
> The docs' example works. One condition the page doesn't state: **all Pods must run at the same time**. With `parallelism` <
> `completions`, the running Pods wait forever for a Pod that can't start (Lab 2).

## Key ideas (read first)

| Piece | Why |
|---|---|
| `completionMode: Indexed` | stable hostnames `example-job-0`, `-1`, `-2` |
| headless Service selecting `job-name: example-job` | creates DNS records for the Pods |
| `subdomain: headless-svc` in the Pod template | gives each Pod the name `<hostname>.headless-svc` (`.default.svc.cluster.local`) |
| DNS needs a **Ready** Pod | names show up only once a Pod is ready; the script retries until then |

---

## Lab 1 – The docs' Job
```bash
cd tasks/job/job-with-pod-to-pod-communication
kubectl apply -f example-job.yaml
kubectl wait --for=condition=complete --timeout=180s job/example-job
kubectl get job example-job                              # Complete   3/3   8s
kubectl logs -l job-name=example-job,batch.kubernetes.io/job-completion-index=0
#   Failed to ping pod example-job-0.headless-svc, retrying in 1 second...    <- even its own name: not Ready yet
#   Successfully pinged pod: example-job-0.headless-svc
#   Failed to ping pod example-job-1.headless-svc, retrying in 1 second...
#   Failed to ping pod example-job-1.headless-svc, retrying in 1 second...
#   Successfully pinged pod: example-job-1.headless-svc
#   Successfully pinged pod: example-job-2.headless-svc
kubectl delete -f example-job.yaml
```

## Lab 2 – Not all Pods at once → deadlock (not from the docs)
```bash
sed -e 's/parallelism: 3/parallelism: 2/' example-job.yaml | kubectl apply -f -
kubectl get job example-job                              # Running   0/3   61s   … forever
kubectl get pods -l job-name=example-job                 # only example-job-0 and -1
kubectl get endpointslices -l kubernetes.io/service-name=headless-svc \
  -o jsonpath='{range .items[*].endpoints[*]}{.hostname} ready={.conditions.ready}{"\n"}{end}'
#   example-job-0 ready=true
#   example-job-1 ready=true
kubectl logs -l job-name=example-job,batch.kubernetes.io/job-completion-index=0 | sort | uniq -c
#   62 Failed to ping pod example-job-2.headless-svc, retrying in 1 second...
#      <- index 2 needs a free slot; the slots are held by Pods waiting for index 2
kubectl delete -f example-job.yaml
```
For real distributed jobs (MPI, PyTorch), set `parallelism == completions` and use a timeout. If the hostnames must resolve before
the Pods are Ready, add `publishNotReadyAddresses: true` to the Service.

## Cleanup
```bash
./cleanup.sh
```
