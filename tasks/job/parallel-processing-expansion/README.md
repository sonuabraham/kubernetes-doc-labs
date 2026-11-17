# Parallel Processing using Expansions – Hands-on Lab

Based on: https://kubernetes.io/docs/tasks/job/parallel-processing-expansion/

> Runs on the default **minikube** cluster, `default` namespace. Files (docs, **verbatim**): [job-tmpl.yaml](job-tmpl.yaml),
> [job.yaml.jinja2](job.yaml.jinja2). The generated `jobs/` folder and `jobs.yaml` aren't committed: [cleanup.sh](cleanup.sh) removes them.
>
> **Found:** the `render_template` alias calls `python`. Many systems (this Ubuntu host too) only have `python3`, so it fails with
> `python: command not found`. Use `python3` (needs `jinja2`: `pip install jinja2` or the distro package).

## Key ideas (read first)

| Topic | Meaning |
|---|---|
| Pattern | one **Job per work item**, generated from a template outside Kubernetes |
| `$ITEM` / Jinja | Kubernetes doesn't expand anything: the placeholders are filled in **before** `kubectl` sees the YAML |
| Common label `jobgroup=jobexample` | lets you get/log/delete the whole group at once (the key isn't special) |
| Automatic labels | `job-name`, `controller-uid` (+ `batch.kubernetes.io/` versions) tell the Jobs' Pods apart |
| Limits | many Jobs = API load, 429 rate limiting, object-count quotas → consider an Indexed Job instead |

---

## Lab 1 – sed expansion (docs)
```bash
cd tasks/job/parallel-processing-expansion
mkdir ./jobs
for i in apple banana cherry
do
  cat job-tmpl.yaml | sed "s/\$ITEM/$i/" > ./jobs/job-$i.yaml
done
ls jobs/                                     # job-apple.yaml  job-banana.yaml  job-cherry.yaml
kubectl create -f ./jobs
#   job.batch/process-item-apple created  (… banana, cherry)
kubectl get jobs -l jobgroup=jobexample
#   process-item-apple    Complete   1/1   8s   8s   (×3)
kubectl get pods -l jobgroup=jobexample      # 3 × Completed
kubectl logs -f -l jobgroup=jobexample
#   Processing item apple
#   Processing item cherry                   <- order isn't guaranteed
#   Processing item banana
kubectl get pod -l jobgroup=jobexample -o jsonpath='{.items[0].metadata.labels}'
#   {"batch.kubernetes.io/controller-uid":"…","batch.kubernetes.io/job-name":"process-item-apple","controller-uid":"…","job-name":"process-item-apple","jobgroup":"jobexample"}
kubectl delete job -l jobgroup=jobexample
```

## Lab 2 – Jinja with several parameters (docs, python3)
```bash
alias render_template='python3 -c "from jinja2 import Template; import sys; print(Template(sys.stdin.read()).render());"'
cat job.yaml.jinja2 | render_template > jobs.yaml
grep -E 'name: jobexample-|command' jobs.yaml
#   name: jobexample-apple
#       command: ["sh", "-c", "echo Processing URL http://dbpedia.org/resource/Apple && sleep 5"]
#   … banana, cherry
cat job.yaml.jinja2 | render_template | kubectl apply -f -
kubectl logs -l jobgroup=jobexample
#   Processing URL http://dbpedia.org/resource/Apple
#   Processing URL http://dbpedia.org/resource/Banana
#   Processing URL http://dbpedia.org/resource/Cherry
kubectl delete job -l jobgroup=jobexample
```
The URL can't be part of a Job name (`/`, `:` aren't allowed), which is why the template has a separate `name` parameter.
Compare with [indexed-parallel-processing-static](../indexed-parallel-processing-static/): one Job, N indexes, no templating.

## Cleanup
```bash
./cleanup.sh
```
