// lab-dra-driver: a small but REAL DRA driver for the "Assign Devices to Pods and Containers" labs, built with
// the DRA kubelet plugin library (k8s.io/dynamic-resource-allocation/kubeletplugin). NOT for production.
//
//	lab-dra-driver -driver driver.example.com -kubeconfig /etc/kubernetes/admin.conf -node <node> -gpus 4
//
// What it does, like a vendor driver:
//   - registers with the kubelet (plugin registration socket) and serves the DRA gRPC API
//   - publishes a ResourceSlice for this node: N fake GPUs, attributes type/model/uuid/driverVersion, capacity memory 64Gi
//   - Prepare: for each allocated device, writes a CDI spec (/var/run/cdi) that injects environment variables
//     (GPU_DEVICE_<n>=gpu-x) into the containers using the claim - so the container really "gets" the device
//   - Unprepare: removes those CDI specs
//   - device metadata (beta 1.37): EnableDeviceMetadata makes the framework bind-mount JSON metadata files
//     (/var/run/kubernetes.io/dra-device-attributes/...) into the containers
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	resourceapi "k8s.io/api/resource/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/dynamic-resource-allocation/kubeletplugin"
	"k8s.io/dynamic-resource-allocation/resourceslice"
	"k8s.io/klog/v2"
)

const cdiDir = "/var/run/cdi"

type driver struct {
	name string
	node string
}

func (d *driver) cdiKind() string { return d.name + "/gpu" } // "<vendor>/<class>"

func (d *driver) cdiFile(claimUID types.UID) string {
	return filepath.Join(cdiDir, fmt.Sprintf("%s-%s.json", strings.ReplaceAll(d.name, ".", "_"), claimUID))
}

// PrepareResourceClaims: called by the kubelet before containers start.
func (d *driver) PrepareResourceClaims(ctx context.Context, claims []*resourceapi.ResourceClaim) (map[types.UID]kubeletplugin.PrepareResult, error) {
	out := map[types.UID]kubeletplugin.PrepareResult{}
	for _, claim := range claims {
		var devs []kubeletplugin.Device
		type cdiDev struct {
			Name           string `json:"name"`
			ContainerEdits struct {
				Env []string `json:"env"`
			} `json:"containerEdits"`
		}
		var spec struct {
			CDIVersion string   `json:"cdiVersion"`
			Kind       string   `json:"kind"`
			Devices    []cdiDev `json:"devices"`
		}
		spec.CDIVersion, spec.Kind = "0.6.0", d.cdiKind()
		if claim.Status.Allocation == nil {
			out[claim.UID] = kubeletplugin.PrepareResult{Err: fmt.Errorf("claim %s not allocated", claim.Name)}
			continue
		}
		for i, r := range claim.Status.Allocation.Devices.Results {
			if r.Driver != d.name {
				continue
			}
			cdiName := fmt.Sprintf("%s-%s", claim.UID, r.Device)
			cd := cdiDev{Name: cdiName}
			cd.ContainerEdits.Env = []string{
				fmt.Sprintf("GPU_DEVICE_%d=%s", i, r.Device),
				fmt.Sprintf("GPU_DEVICE_%d_REQUEST=%s", i, r.Request),
				fmt.Sprintf("GPU_DEVICE_%d_CLAIM=%s/%s", i, claim.Namespace, claim.Name),
			}
			spec.Devices = append(spec.Devices, cd)
			model, uuid := "lab-gpu-64g", fmt.Sprintf("GPU-%s-%s", d.node, r.Device)
			devs = append(devs, kubeletplugin.Device{
				Requests:     []string{r.Request},
				PoolName:     r.Pool,
				DeviceName:   r.Device,
				CDIDeviceIDs: []string{d.cdiKind() + "=" + cdiName},
				Metadata: &kubeletplugin.DeviceMetadata{Attributes: map[string]resourceapi.DeviceAttribute{
					"type":  {StringValue: ptr("gpu")},
					"model": {StringValue: &model},
					"uuid":  {StringValue: &uuid},
				}},
			})
		}
		b, _ := json.MarshalIndent(spec, "", "  ")
		if err := os.WriteFile(d.cdiFile(claim.UID), b, 0o644); err != nil {
			out[claim.UID] = kubeletplugin.PrepareResult{Err: err}
			continue
		}
		klog.Infof("prepared claim %s/%s: %d device(s), CDI spec %s", claim.Namespace, claim.Name, len(devs), d.cdiFile(claim.UID))
		out[claim.UID] = kubeletplugin.PrepareResult{Devices: devs}
	}
	return out, nil
}

// UnprepareResourceClaims: called after the last container using the claim is gone.
func (d *driver) UnprepareResourceClaims(ctx context.Context, claims []kubeletplugin.NamespacedObject) (map[types.UID]error, error) {
	out := map[types.UID]error{}
	for _, c := range claims {
		err := os.Remove(d.cdiFile(c.UID))
		if os.IsNotExist(err) {
			err = nil
		}
		klog.Infof("unprepared claim %s (%s)", c.NamespacedName, c.UID)
		out[c.UID] = err
	}
	return out, nil
}

func (d *driver) HandleError(ctx context.Context, err error, msg string) {
	klog.ErrorS(err, msg)
}

// WatchHealthStatus: device health reporting (KEP-4680). Not used by this lab driver: the health service is
// disabled with kubeletplugin.HealthService(false), so this is never called.
func (d *driver) WatchHealthStatus(ctx context.Context, reports chan<- kubeletplugin.DeviceHealthReport) error {
	<-ctx.Done()
	return nil
}

func ptr[T any](v T) *T { return &v }

func main() {
	klog.InitFlags(nil)
	name := flag.String("driver", "driver.example.com", "DRA driver name")
	kubeconfig := flag.String("kubeconfig", "/etc/kubernetes/admin.conf", "kubeconfig used to publish ResourceSlices")
	node := flag.String("node", "", "this node's name")
	gpus := flag.Int("gpus", 4, "number of fake GPUs to publish")
	flag.Parse()
	if *node == "" {
		h, _ := os.Hostname()
		*node = h
	}
	cfg, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil {
		klog.Fatal(err)
	}
	client := kubernetes.NewForConfigOrDie(cfg)
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	if err := os.MkdirAll(cdiDir, 0o755); err != nil {
		klog.Fatal(err)
	}

	d := &driver{name: *name, node: *node}
	helper, err := kubeletplugin.Start(ctx, d,
		kubeletplugin.DriverName(*name),
		kubeletplugin.NodeName(*node),
		kubeletplugin.KubeClient(client),
		kubeletplugin.HealthService(false),
		kubeletplugin.EnableDeviceMetadata(true, []schema.GroupVersion{{Group: "metadata.resource.k8s.io", Version: "v1beta1"}}),
	)
	if err != nil {
		klog.Fatal(err)
	}
	defer helper.Stop()

	var devices []resourceapi.Device
	for i := 0; i < *gpus; i++ {
		devices = append(devices, resourceapi.Device{
			Name: fmt.Sprintf("gpu-%d", i),
			Attributes: map[resourceapi.QualifiedName]resourceapi.DeviceAttribute{
				"type":          {StringValue: ptr("gpu")},
				"model":         {StringValue: ptr("lab-gpu-64g")},
				"uuid":          {StringValue: ptr(fmt.Sprintf("GPU-%s-gpu-%d", *node, i))},
				"index":         {IntValue: ptr(int64(i))},
				"driverVersion": {VersionValue: ptr("1.0.0")},
			},
			Capacity: map[resourceapi.QualifiedName]resourceapi.DeviceCapacity{
				"memory": {Value: resource.MustParse("64Gi")},
			},
		})
	}
	if err := helper.PublishResources(ctx, resourceslice.DriverResources{
		Pools: map[string]resourceslice.Pool{*node: {Slices: []resourceslice.Slice{{Devices: devices}}}},
	}); err != nil {
		klog.Fatal(err)
	}
	klog.Infof("%s running on node %s with %d GPUs", *name, *node, *gpus)
	<-ctx.Done()
}
