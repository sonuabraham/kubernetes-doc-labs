#!/usr/bin/env python3
"""Minimal PodResources API client (what a device-monitoring agent does).
   podresources.py list                  -> List: devices/CPUs of all running Pods (only Pods that have some)
   podresources.py allocatable           -> GetAllocatableResources
   podresources.py get <pod> <namespace> -> Get (beta since v1.34)
Talks to /var/lib/kubelet/pod-resources/kubelet.sock (mount the DIRECTORY, not the socket).
Prints one line per device group. (NUMA node IDs are read from the message directly: proto3 omits a
zero ID when converting to JSON, so node 0 would show up as {}.)"""
import sys, grpc
import podresources_pb2 as pb
import podresources_pb2_grpc as pbg

stub = pbg.PodResourcesListerStub(grpc.insecure_channel("unix:///var/lib/kubelet/pod-resources/kubelet.sock"))


def devs(devices):
    return [f"{d.resource_name} {list(d.device_ids)} numa={[n.ID for n in d.topology.nodes]}" for d in devices]


def show_pod(p):
    for c in p.containers:
        mem = [f"memory {m.memory_type} {m.size} bytes numa={[n.ID for n in m.topology.nodes]}" for m in c.memory]
        for line in devs(c.devices) + ([f"exclusive cpus {list(c.cpu_ids)}"] if c.cpu_ids else []) + mem + \
                [f"DRA claim {r.claim_namespace}/{r.claim_name}" for r in c.dynamic_resources]:
            print(f"  {p.namespace}/{p.name}/{c.name}: {line}")


cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
if cmd == "list":
    for p in stub.List(pb.ListPodResourcesRequest()).pod_resources:
        show_pod(p)
elif cmd == "allocatable":
    r = stub.GetAllocatableResources(pb.AllocatableResourcesRequest())
    for line in devs(r.devices):
        print("  " + line)
    print(f"  cpus {list(r.cpu_ids)}")
    for m in r.memory:
        print(f"  memory {m.memory_type} {m.size} bytes numa={[n.ID for n in m.topology.nodes]}")
elif cmd == "get":
    show_pod(stub.Get(pb.GetPodResourcesRequest(pod_name=sys.argv[2], pod_namespace=sys.argv[3])).pod_resources)
