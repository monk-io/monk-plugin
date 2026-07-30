package instance

import (
	"github.com/docker/go-connections/nat"
)

type ContainerConfig struct {
	Image        string
	Name         string
	Cmd          []string
	Env          []string
	Volumes      map[string]string
	PortBindings nat.PortMap
	NetworkMode  string
	Labels       map[string]string
}

type ContainerStatus struct {
	Running      bool              `json:"Running"`
	Status       string            `json:"Status"`
	Ports        map[string]string `json:"Ports"`
	PublicPorts  map[string]string `json:"PublicPorts"`
	RestartCount int               `json:"RestartCount"`
}

type DeploymentEvent struct {
	Type      string      `json:"type"`
	Message   string      `json:"message"`
	Timestamp int64       `json:"timestamp"`
	Data      interface{} `json:"data,omitempty"`
}

type DeploymentResult struct {
	Status     string             `json:"status"`
	Message    string             `json:"message"`
	Events     []DeploymentEvent  `json:"events"`
	Containers []ContainerStatus  `json:"containers"`
	Endpoints  []ServiceEndpoint  `json:"endpoints,omitempty"`
}

type ServiceEndpoint struct {
	Service   string `json:"service"`
	Protocol  string `json:"protocol"`
	Port      int    `json:"port"`
	HostPort  string `json:"host_port"`
	URL       string `json:"url"`
}
