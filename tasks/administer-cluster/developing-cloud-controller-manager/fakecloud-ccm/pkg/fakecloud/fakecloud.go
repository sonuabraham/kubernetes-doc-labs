// Package fakecloud is a minimal cloudprovider.Interface implementation for an imaginary cloud "fakecloud".
// Step 1 of the docs: "Create a go package with an implementation that satisfies cloudprovider.Interface".
// Step 3: the package registers itself in init() with cloudprovider.RegisterCloudProvider.
//
// "The cloud" is a JSON file (--cloud-config) describing the VMs that exist:
//
//	{"region": "eu-lab-1", "instances": {"<node-name>": {"zone": "eu-lab-1a", "type": "fake.large"}}}
//
// It implements InstancesV2 (used by the cloud node + node lifecycle controllers) and LoadBalancer (used by the
// service controller). Zones/Routes/Clusters/Instances(v1) report "not implemented" via false.
package fakecloud

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"sync"

	v1 "k8s.io/api/core/v1"
	cloudprovider "k8s.io/cloud-provider"
	"k8s.io/klog/v2"
)

const ProviderName = "fakecloud"

type instance struct {
	Zone string `json:"zone"`
	Type string `json:"type"`
}

type config struct {
	Region    string              `json:"region"`
	Instances map[string]instance `json:"instances"`
}

// Cloud is the provider; it is both the cloudprovider.Interface and its sub-interfaces.
type Cloud struct {
	cfg config

	mu     sync.Mutex
	lbs    map[string]string // service UID -> allocated IP
	nextIP int
}

func init() {
	cloudprovider.RegisterCloudProvider(ProviderName, func(r io.Reader) (cloudprovider.Interface, error) {
		c := &Cloud{lbs: map[string]string{}, nextIP: 200}
		if r == nil {
			return nil, fmt.Errorf("fakecloud needs --cloud-config")
		}
		if err := json.NewDecoder(r).Decode(&c.cfg); err != nil {
			return nil, fmt.Errorf("reading cloud config: %w", err)
		}
		klog.Infof("fakecloud: region %q with %d instances", c.cfg.Region, len(c.cfg.Instances))
		return c, nil
	})
}

// ---- cloudprovider.Interface ----

func (c *Cloud) Initialize(cloudprovider.ControllerClientBuilder, <-chan struct{}) {}
func (c *Cloud) LoadBalancer() (cloudprovider.LoadBalancer, bool)                  { return c, true }
func (c *Cloud) Instances() (cloudprovider.Instances, bool)                        { return nil, false }
func (c *Cloud) InstancesV2() (cloudprovider.InstancesV2, bool)                    { return c, true }
func (c *Cloud) Zones() (cloudprovider.Zones, bool)                                { return nil, false }
func (c *Cloud) Clusters() (cloudprovider.Clusters, bool)                          { return nil, false }
func (c *Cloud) Routes() (cloudprovider.Routes, bool)                              { return nil, false }
func (c *Cloud) ProviderName() string                                              { return ProviderName }
func (c *Cloud) HasClusterID() bool                                                { return true }

// ---- InstancesV2: node controller (initialize nodes) + node lifecycle controller (delete vanished VMs) ----

func (c *Cloud) InstanceExists(_ context.Context, node *v1.Node) (bool, error) {
	_, ok := c.cfg.Instances[node.Name]
	klog.Infof("fakecloud: InstanceExists(%s) = %v", node.Name, ok)
	return ok, nil
}

func (c *Cloud) InstanceShutdown(context.Context, *v1.Node) (bool, error) { return false, nil }

func (c *Cloud) InstanceMetadata(_ context.Context, node *v1.Node) (*cloudprovider.InstanceMetadata, error) {
	vm, ok := c.cfg.Instances[node.Name]
	if !ok {
		return nil, cloudprovider.InstanceNotFound
	}
	md := &cloudprovider.InstanceMetadata{
		ProviderID:       fmt.Sprintf("%s://%s/%s", ProviderName, vm.Zone, node.Name),
		InstanceType:     vm.Type,
		Region:           c.cfg.Region,
		Zone:             vm.Zone,
		NodeAddresses:    node.Status.Addresses, // a real cloud would look these up in its API
		AdditionalLabels: map[string]string{"fakecloud.example.com/managed": "true"},
	}
	klog.Infof("fakecloud: InstanceMetadata(%s) = %s %s/%s", node.Name, md.ProviderID, md.Region, md.Zone)
	return md, nil
}

// ---- LoadBalancer: service controller (type: LoadBalancer) ----

func (c *Cloud) GetLoadBalancerName(_ context.Context, cluster string, svc *v1.Service) string {
	return fmt.Sprintf("%s-%s-%s", cluster, svc.Namespace, svc.Name)
}

func (c *Cloud) GetLoadBalancer(_ context.Context, _ string, svc *v1.Service) (*v1.LoadBalancerStatus, bool, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	ip, ok := c.lbs[string(svc.UID)]
	if !ok {
		return nil, false, nil
	}
	return &v1.LoadBalancerStatus{Ingress: []v1.LoadBalancerIngress{{IP: ip}}}, true, nil
}

func (c *Cloud) EnsureLoadBalancer(ctx context.Context, cluster string, svc *v1.Service, nodes []*v1.Node) (*v1.LoadBalancerStatus, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	ip, ok := c.lbs[string(svc.UID)]
	if !ok {
		ip = fmt.Sprintf("203.0.113.%d", c.nextIP) // TEST-NET-3: documentation addresses
		c.nextIP++
		c.lbs[string(svc.UID)] = ip
	}
	klog.Infof("fakecloud: EnsureLoadBalancer(%s) -> %s, backends: %d nodes", c.GetLoadBalancerName(ctx, cluster, svc), ip, len(nodes))
	return &v1.LoadBalancerStatus{Ingress: []v1.LoadBalancerIngress{{IP: ip}}}, nil
}

func (c *Cloud) UpdateLoadBalancer(ctx context.Context, cluster string, svc *v1.Service, nodes []*v1.Node) error {
	klog.Infof("fakecloud: UpdateLoadBalancer(%s), backends: %d nodes", c.GetLoadBalancerName(ctx, cluster, svc), len(nodes))
	return nil
}

func (c *Cloud) EnsureLoadBalancerDeleted(ctx context.Context, cluster string, svc *v1.Service) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	klog.Infof("fakecloud: EnsureLoadBalancerDeleted(%s) - releasing %s", c.GetLoadBalancerName(ctx, cluster, svc), c.lbs[string(svc.UID)])
	delete(c.lbs, string(svc.UID))
	return nil
}
