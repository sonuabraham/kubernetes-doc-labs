# Coarse Parallel Processing Using a Work Queue – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/job/coarse-parallel-processing-work-queue/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [rabbitmq-service.yaml](rabbitmq-service.yaml),
> [rabbitmq-statefulset.yaml](rabbitmq-statefulset.yaml), [Dockerfile](Dockerfile), [worker.py](worker.py), [job.yaml](job.yaml).
> [job-local.yaml](job-local.yaml) = `job.yaml` with the image edit the page asks for (local image + `imagePullPolicy: Never`).
> No registry needed: `minikube image build` builds the image straight into the node.
>
> **Found:**
> 1. "Fill the queue … Run this on your computer, not in the Pod" is wrong. `$BROKER_URL` points to `rabbitmq-service`, which only resolves
>    **inside** the cluster, so run it in the `temp` Pod like the earlier steps.
> 2. The Dockerfile still uses `ubuntu:18.04` (EOL) and Python 2 (`python`). It still builds, but expect that to break one day.
> 3. The interactive `kubectl run -i --tty temp` becomes `kubectl run temp … -- sleep 3600` + `kubectl exec` here (same commands).

## Key ideas (read first)

| Piece | Role |
|---|---|
| RabbitMQ (StatefulSet + Service) | the work queue `job1` holds 8 messages (= 8 tasks) |
| `amqp-consume -c 1 /worker.py` | takes **one** message, pipes it to the worker, acks, exits. The worker doesn't know about the queue |
| Job `completions: 8`, `parallelism: 2` | 8 Pods total, 2 at a time, **one task per Pod** |
| Caveat | `completions` must equal the number of items: more = Pods block forever, fewer = items left over |

---

## Lab 1 – Queue service (docs)
```bash
cd tasks/job/coarse-parallel-processing-work-queue
kubectl create -f rabbitmq-service.yaml
kubectl create -f rabbitmq-statefulset.yaml
kubectl run temp --image ubuntu:22.04 -- sleep 3600
kubectl exec temp -- sh -c 'apt-get update && apt-get install -y curl ca-certificates amqp-tools python3 dnsutils'
kubectl exec temp -- nslookup rabbitmq-service          # Address: 10.98.103.143
kubectl exec temp -- sh -c 'env | grep RABBITMQ_SERVICE | grep HOST'      # RABBITMQ_SERVICE_SERVICE_HOST=10.98.103.143
kubectl logs rabbitmq-0 | grep "Server startup complete"   # wait for this
kubectl exec -it temp -- bash
  export BROKER_URL=amqp://guest:guest@rabbitmq-service:5672
  /usr/bin/amqp-declare-queue --url=$BROKER_URL -q foo -d                  # foo
  /usr/bin/amqp-publish --url=$BROKER_URL -r foo -p -b Hello
  /usr/bin/amqp-consume --url=$BROKER_URL -q foo -c 1 cat && echo 1>&2     # Hello
  /usr/bin/amqp-declare-queue --url=$BROKER_URL -q job1  -d                # job1   (in the Pod, not "on your computer")
  for f in apple banana cherry date fig grape lemon melon; do /usr/bin/amqp-publish --url=$BROKER_URL -r job1 -p -b $f; done
  exit
kubectl exec rabbitmq-0 -- rabbitmqctl list_queues -q
#   job1   8
#   foo    0
```

## Lab 2 – Image and Job (docs)
```bash
minikube image build -t job-wq-1 .                       # instead of docker build + push
kubectl apply -f ./job-local.yaml
kubectl wait --for=condition=complete --timeout=300s job/job-wq-1         # ~52 s (8 × 10 s / 2 + Pod start)
kubectl describe jobs/job-wq-1 | grep -E 'Parallelism|Completions|Completion Mode|Pods Statuses'
#   Parallelism:      2
#   Completions:      8
#   Completion Mode:  NonIndexed
#   Pods Statuses:    0 Active (0 Ready) / 8 Succeeded / 0 Failed
for p in $(kubectl get pods -l job-name=job-wq-1 -o name --sort-by=.status.startTime); do kubectl logs $p; done
#   Processing apple / banana / date / cherry / grape / fig / lemon / melon   <- order within each pair varies
kubectl exec rabbitmq-0 -- rabbitmqctl list_queues -q    # job1 0
```
The docs' `describe` output is old: the selector is now `batch.kubernetes.io/controller-uid=…`.

## Lab 3 – Caveat: more completions than items (not from the docs)
```bash
kubectl exec temp -- bash -c 'for f in x y z; do /usr/bin/amqp-publish --url=amqp://guest:guest@rabbitmq-service:5672 -r job1 -p -b $f; done'
sed -e 's/name: job-wq-1$/name: job-wq-short/' -e 's/completions: 8/completions: 5/' job-local.yaml | kubectl apply -f -
kubectl get job job-wq-short                             # Running   3/5   … and stays so
kubectl get pods -l job-name=job-wq-short                # 3 Completed, 2 Running (waiting for messages)
kubectl exec rabbitmq-0 -- rabbitmqctl list_consumers -q # 2 consumers on job1, blocked
```

## Cleanup
```bash
./cleanup.sh
```
