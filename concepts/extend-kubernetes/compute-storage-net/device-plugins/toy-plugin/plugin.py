#!/usr/bin/env python3
"""Toy device plugin for the resource hardware-vendor.example/foo (the docs' example name).

It follows the workflow on the docs page:
  1. "Initialization": creates one directory per fake device under /var/lib/toy-foo on the node.
  2. Serves the DevicePlugin gRPC service on /var/lib/kubelet/device-plugins/toy-foo.sock.
  3. Registers with the kubelet via /var/lib/kubelet/device-plugins/kubelet.sock (only AFTER serving).
  4. Serving mode: ListAndWatch streams device health; Allocate tells the kubelet what to inject.
  5. Watches its socket: a restarting kubelet deletes it, so the plugin re-serves and re-registers.

Device health: write device IDs (one per line) to /run/toy/unhealthy inside this container
(kubectl exec ... -- sh -c 'echo foo-1 > /run/toy/unhealthy'); empty the file to heal them.
"""
import os, time, threading, logging
from concurrent import futures
import grpc
import deviceplugin_pb2 as pb
import deviceplugin_pb2_grpc as pbg

RESOURCE = os.environ.get("RESOURCE", "hardware-vendor.example/foo")
N = int(os.environ.get("DEVICES", "4"))
DP_DIR = "/var/lib/kubelet/device-plugins"
SOCK = "toy-foo.sock"
HOST_DIR = "/var/lib/toy-foo"          # hostPath, so the kubelet can mount it into workload containers
UNHEALTHY = "/run/toy/unhealthy"
IDS = [f"foo-{i}" for i in range(N)]
logging.basicConfig(format="%(asctime)s %(message)s", datefmt="%H:%M:%S", level=logging.INFO)
log = logging.info


def unhealthy():
    try:
        return {l.strip() for l in open(UNHEALTHY) if l.strip()}
    except FileNotFoundError:
        return set()


def device_list():
    bad = unhealthy()
    return [pb.Device(ID=d, health="Unhealthy" if d in bad else "Healthy",
                      topology=pb.TopologyInfo(nodes=[pb.NUMANode(ID=0)])) for d in IDS]


class Toy(pbg.DevicePluginServicer):
    def GetDevicePluginOptions(self, request, context):
        log("GetDevicePluginOptions")
        return pb.DevicePluginOptions(pre_start_required=True, get_preferred_allocation_available=True)

    def ListAndWatch(self, request, context):
        last = None
        while context.is_active():
            devs = device_list()
            state = [(d.ID, d.health) for d in devs]
            if state != last:
                log("ListAndWatch -> " + ", ".join(f"{i}={h}" for i, h in state))
                yield pb.ListAndWatchResponse(devices=devs)
                last = state
            time.sleep(1)

    def GetPreferredAllocation(self, request, context):
        out = []
        for r in request.container_requests:
            # policy: keep must-include devices, then prefer the HIGHEST ids (so it's visible)
            pick = list(r.must_include_deviceIDs)
            for d in sorted(r.available_deviceIDs, reverse=True):
                if len(pick) >= r.allocation_size:
                    break
                if d not in pick:
                    pick.append(d)
            log(f"GetPreferredAllocation available={list(r.available_deviceIDs)} size={r.allocation_size} -> {pick}")
            out.append(pb.ContainerPreferredAllocationResponse(deviceIDs=pick))
        return pb.PreferredAllocationResponse(container_responses=out)

    def Allocate(self, request, context):
        out = []
        for r in request.container_requests:
            ids = sorted(r.devices_ids)
            log(f"Allocate {ids}")
            out.append(pb.ContainerAllocateResponse(
                envs={"FOO_DEVICES": ",".join(ids)},
                annotations={"hardware-vendor.example/foo-devices": ",".join(ids)},
                # device nodes: map the node's /dev/null in as /dev/<id> (a real char device, harmless)
                devices=[pb.DeviceSpec(container_path=f"/dev/{d}", host_path="/dev/null", permissions="rw") for d in ids],
                mounts=[pb.Mount(container_path=f"/etc/foo/{d}", host_path=f"{HOST_DIR}/{d}", read_only=True) for d in ids],
            ))
        return pb.AllocateResponse(container_responses=out)

    def PreStartContainer(self, request, context):
        log(f"PreStartContainer {list(request.devices_ids)}  (e.g. reset the device)")
        return pb.PreStartContainerResponse()


def serve():
    path = os.path.join(DP_DIR, SOCK)
    if os.path.exists(path):
        os.remove(path)
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
    pbg.add_DevicePluginServicer_to_server(Toy(), server)
    server.add_insecure_port(f"unix://{path}")
    server.start()
    log(f"serving on {path}")
    return server, path


def register():
    with grpc.insecure_channel(f"unix://{DP_DIR}/kubelet.sock") as ch:
        pbg.RegistrationStub(ch).Register(pb.RegisterRequest(
            version="v1beta1", endpoint=SOCK, resource_name=RESOURCE,
            options=pb.DevicePluginOptions(pre_start_required=True, get_preferred_allocation_available=True)))
    log(f"registered {RESOURCE} with the kubelet")


def main():
    for d in IDS:                                    # 1. initialization
        os.makedirs(f"{HOST_DIR}/{d}", exist_ok=True)
        with open(f"{HOST_DIR}/{d}/info", "w") as f:
            f.write(f"toy foo device {d}\n")
    os.makedirs(os.path.dirname(UNHEALTHY), exist_ok=True)
    while True:
        server, path = serve()                       # 2. serve first ...
        register()                                   # 3. ... then register
        while os.path.exists(path):                  # 5. kubelet restart deletes our socket
            time.sleep(1)
        log("socket deleted (kubelet restarted?) -> re-serving and re-registering")
        server.stop(0)
        time.sleep(1)


if __name__ == "__main__":
    main()
