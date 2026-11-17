# Fine Parallel Processing Using a Work Queue – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/job/fine-parallel-processing-work-queue/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [redis-pod.yaml](redis-pod.yaml),
> [redis-service.yaml](redis-service.yaml), [Dockerfile](Dockerfile), [rediswq.py](rediswq.py), [worker.py](worker.py), [job.yaml](job.yaml).
> [job-local.yaml](job-local.yaml) = `job.yaml` with the image edit the page asks for (local image + `imagePullPolicy: Never`).
>
> **Found:**
> 1. `kubectl logs` of a running worker is **empty**. Python buffers stdout when it isn't a terminal, so all lines appear when the worker exits.
>    Use `python -u` or `PYTHONUNBUFFERED=1` to watch live.
> 2. `rediswq.py` never gives back expired leases (its `check_expired_leases` is a TODO). If a worker dies mid-item, the item stays in
>    `job2:processing` forever. The replacement Pod loops "Waiting for work" and **the Job never completes** (Lab 3).

## Key ideas (read first)

| Piece | Role |
|---|---|
| Redis list `job2` | the queue; `rpush` adds, the worker `brpoplpush`es from the right into `job2:processing` (so newest item first) |
| Lease | `job2:leased_by_session:<sha224>` with a TTL; deleted by `complete()` |
| Job `parallelism: 2`, **no `completions`** | each Pod processes **many** items; the first Pod to exit 0 marks the work done, then the Job waits for the rest |
| `empty()` | main **and** processing list empty; a worker keeps waiting while another worker still holds an item |

---

## Lab 1 – Redis and the queue (docs)
```bash
cd tasks/job/fine-parallel-processing-work-queue
kubectl apply -f redis-pod.yaml
kubectl apply -f redis-service.yaml
kubectl run temp --image redis --command -- sleep 3600           # docs: kubectl run -i --tty temp --image redis --command "/bin/sh"
kubectl exec temp -- sh -c 'for f in apple banana cherry date fig grape lemon melon orange; do redis-cli -h redis rpush job2 "$f"; done'
#   (integer) 1 … 9
kubectl exec temp -- redis-cli -h redis lrange job2 0 -1        # apple … orange
```

## Lab 2 – Image and Job (docs)
```bash
minikube image build -t job-wq-2 .                               # instead of docker build + push
kubectl apply -f ./job-local.yaml
kubectl describe jobs/job-wq-2 | grep -E 'Parallelism|Completions|Pods Statuses'
#   Parallelism:      2
#   Completions:      <unset>
#   Pods Statuses:    2 Active (2 Ready) / 0 Succeeded / 0 Failed
kubectl wait --for=condition=complete --timeout=300s job/job-wq-2     # ~53 s for 9 items × 10 s on 2 workers
kubectl get job job-wq-2                                         # Complete   2/1 of 2
for p in $(kubectl get pods -l job-name=job-wq-2 -o name); do kubectl logs $p; done
#   Worker with sessionID: 0aacbc47-…            Worker with sessionID: 567e3282-…
#   Initial queue state: empty=False             Initial queue state: empty=False
#   Working on orange / lemon / fig /            Working on melon / grape / date / banana
#              cherry / apple                    Waiting for work  (×5)   <- other worker still had "apple"
#   Queue empty, exiting                         Queue empty, exiting
```

## Lab 3 – A worker dies mid-item (not from the docs)
```bash
kubectl exec temp -- redis-cli -h redis rpush job2 kiwi mango
sed -e 's/name: job-wq-2$/name: job-wq-crash/' -e 's/parallelism: 2/parallelism: 1/' job-local.yaml | kubectl apply -f -
kubectl exec temp -- redis-cli -h redis lrange job2:processing 0 -1     # mango   (wait until it shows)
kubectl logs -l job-name=job-wq-crash                            # (empty: stdout buffered)
kubectl delete pod -l job-name=job-wq-crash --grace-period=1     # the Job starts a replacement
kubectl get job job-wq-crash                                     # Running   0/1   … forever
kubectl exec temp -- sh -c 'echo "main: $(redis-cli -h redis lrange job2 0 -1)"; echo "processing: $(redis-cli -h redis lrange job2:processing 0 -1)"; redis-cli -h redis keys "job2:leased*"'
#   main:                    <- kiwi was done by the replacement
#   processing: mango        <- lease expired after 10 s, but nobody moves it back
#   (no lease keys)
```
A production queue needs lease recovery (or use RabbitMQ acks, as in [coarse-parallel-processing-work-queue](../coarse-parallel-processing-work-queue/)).

## Cleanup
```bash
./cleanup.sh
```
