#!/usr/bin/env python3
"""NOT from the docs. Run ON THE NODE (as root): summarise the kubelet's Memory Manager and CPU Manager
checkpoint files - the "kubelet state file" source the page describes. (1.37 names the docs' "nodes" group field "cells".)
   python3 node-topology-state.py [pod-uid ...]"""
import json, sys
mm = json.load(open("/var/lib/kubelet/memory_manager_state"))
print("memory manager policy:", mm["policyName"])
for numa, st in mm["machineState"].items():
    m = st["memoryMap"]["memory"]
    print(f"  NUMA {numa}: total={m['total']} systemReserved={m['systemReserved']} allocatable={m['allocatable']} "
          f"reserved={m['reserved']} free={m['free']} assignments={st['numberOfAssignments']} group={st.get('cells', st.get('nodes'))}")
for uid, ctrs in mm.get("entries", {}).items():
    if len(sys.argv) > 1 and uid not in sys.argv[1:]:
        continue
    for name, blocks in ctrs.items():
        for b in blocks:
            print(f"  pod {uid[:8]} container {name}: {b['type']} {b['size']} bytes numaAffinity={b['numaAffinity']}")
cpu = json.load(open("/var/lib/kubelet/cpu_manager_state"))
print("cpu manager policy:", cpu["policyName"], "| shared pool:", cpu["defaultCpuSet"])
for uid, ctrs in cpu.get("entries", {}).items():
    for name, cpus in ctrs.items():
        print(f"  pod {uid[:8]} container {name}: exclusive cpus {cpus}")
