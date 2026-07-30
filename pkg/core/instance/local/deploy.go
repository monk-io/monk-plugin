package local

import (
	"context"
	"fmt"
	"time"

	"github.com/monk-io/monk/pkg/core/instance"
	"github.com/monk-io/monk/pkg/manifest"
	"github.com/monk-io/monk/pkg/system/docker"
	"github.com/docker/go-connections/nat"
)

type Deployer struct {
	containerMgr *ContainerManager
	runtime      *docker.Runtime
}

func NewDeployer(runtime *docker.Runtime) *Deployer {
	return &Deployer{
		containerMgr: NewContainerManager(runtime),
		runtime:      runtime,
	}
}

func (d *Deployer) Deploy(ctx context.Context, workload *manifest.Runnable) (*instance.DeploymentResult, error) {
	result := &instance.DeploymentResult{
		Status:     "in_progress",
		Events:     []instance.DeploymentEvent{},
		Containers: []instance.ContainerStatus{},
		Endpoints:  []instance.ServiceEndpoint{},
	}

	d.addEvent(result, "info", "Starting deployment")

	for containerName, containerDef := range workload.Containers {
		config := d.buildContainerConfig(workload, containerName, containerDef)

		status, err := d.containerMgr.StartContainer(ctx, config)
		if err != nil {
			result.Status = "failed"
			result.Message = fmt.Sprintf("Failed to start container %s: %v", containerName, err)
			d.addEvent(result, "error", result.Message)
			return result, err
		}

		if len(config.PortBindings) > 0 {
			if status.Ports != nil && len(status.Ports) > 0 {
				d.addEvent(result, "info", fmt.Sprintf("host ports have been added to container %s", config.Name))
			} else {
				d.addEvent(result, "warning", fmt.Sprintf("port bindings configured but not active on container %s", config.Name))
			}
		} else {
			d.addEvent(result, "info", fmt.Sprintf("container %s started without host port mappings", config.Name))
		}

		result.Containers = append(result.Containers, *status)

		if workload.Services != nil {
			for serviceName, serviceDef := range workload.Services {
				if serviceDef.Container == containerName && status.PublicPorts != nil {
					portKey := fmt.Sprintf("%d/%s", serviceDef.Port, serviceDef.Protocol)
					if hostPort, exists := status.PublicPorts[portKey]; exists {
						endpoint := instance.ServiceEndpoint{
							Service:  serviceName,
							Protocol: serviceDef.Protocol,
							Port:     serviceDef.Port,
							HostPort: hostPort,
							URL:      fmt.Sprintf("%s://127.0.0.1:%s", serviceDef.Protocol, hostPort),
						}
						result.Endpoints = append(result.Endpoints, endpoint)
					}
				}
			}
		}
	}

	result.Status = "succeeded"
	result.Message = fmt.Sprintf("Successfully deployed '%s' locally.", workload.Name)
	d.addEvent(result, "success", result.Message)

	return result, nil
}

func (d *Deployer) buildContainerConfig(workload *manifest.Runnable, name string, def *manifest.Container) *instance.ContainerConfig {
	config := &instance.ContainerConfig{
		Image:   def.Image,
		Name:    fmt.Sprintf("local-%s-%s", workload.Name, name),
		Cmd:     def.Command,
		Env:     def.Environment,
		Volumes: def.Volumes,
		Labels:  map[string]string{"monk.workload": workload.Name},
	}

	if workload.Services != nil {
		portBindings := nat.PortMap{}
		for _, serviceDef := range workload.Services {
			if serviceDef.Container == name {
				containerPort := nat.Port(fmt.Sprintf("%d/%s", serviceDef.Port, serviceDef.Protocol))
				portBindings[containerPort] = []nat.PortBinding{
					{
						HostIP:   "127.0.0.1",
						HostPort: "0",
					},
				}
			}
		}
		if len(portBindings) > 0 {
			config.PortBindings = portBindings
		}
	}

	return config
}

func (d *Deployer) addEvent(result *instance.DeploymentResult, eventType, message string) {
	event := instance.DeploymentEvent{
		Type:      eventType,
		Message:   message,
		Timestamp: time.Now().Unix(),
	}
	result.Events = append(result.Events, event)
}
