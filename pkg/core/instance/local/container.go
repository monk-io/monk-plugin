package local

import (
	"context"
	"fmt"
	"strings"

	"github.com/monk-io/monk/pkg/core/instance"
	"github.com/monk-io/monk/pkg/system/docker"
)

type ContainerManager struct {
	runtime *docker.Runtime
}

func NewContainerManager(runtime *docker.Runtime) *ContainerManager {
	return &ContainerManager{runtime: runtime}
}

func (cm *ContainerManager) StartContainer(ctx context.Context, config *instance.ContainerConfig) (*instance.ContainerStatus, error) {
	containerID, err := cm.runtime.CreateContainer(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("failed to create container: %w", err)
	}

	if err := cm.runtime.StartContainer(ctx, containerID); err != nil {
		return nil, fmt.Errorf("failed to start container: %w", err)
	}

	var portMessage string
	if len(config.PortBindings) > 0 {
		portMessage = fmt.Sprintf("host ports have been added to container %s", containerID)
	} else {
		portMessage = fmt.Sprintf("container %s started without host port mappings", containerID)
	}

	status, err := cm.GetContainerStatus(ctx, containerID)
	if err != nil {
		return nil, fmt.Errorf("%s, but failed to retrieve status: %w", portMessage, err)
	}

	return status, nil
}

func (cm *ContainerManager) GetContainerStatus(ctx context.Context, containerID string) (*instance.ContainerStatus, error) {
	inspect, err := cm.runtime.InspectContainer(ctx, containerID)
	if err != nil {
		return nil, fmt.Errorf("failed to inspect container: %w", err)
	}

	status := &instance.ContainerStatus{
		Running:      inspect.State.Running,
		Status:       inspect.State.Status,
		RestartCount: inspect.RestartCount,
	}

	if inspect.NetworkSettings != nil && inspect.NetworkSettings.Ports != nil {
		ports := make(map[string]string)
		publicPorts := make(map[string]string)

		for containerPort, bindings := range inspect.NetworkSettings.Ports {
			if len(bindings) > 0 {
				hostPort := bindings[0].HostPort
				hostIP := bindings[0].HostIP
				if hostIP == "" || hostIP == "0.0.0.0" {
					hostIP = "127.0.0.1"
				}

				portKey := string(containerPort)
				ports[portKey] = fmt.Sprintf("%s:%s", hostIP, hostPort)
				publicPorts[portKey] = hostPort
			}
		}

		if len(ports) > 0 {
			status.Ports = ports
			status.PublicPorts = publicPorts
		}
	}

	return status, nil
}

func (cm *ContainerManager) StopContainer(ctx context.Context, containerID string) error {
	return cm.runtime.StopContainer(ctx, containerID)
}

func (cm *ContainerManager) RemoveContainer(ctx context.Context, containerID string) error {
	return cm.runtime.RemoveContainer(ctx, containerID)
}
