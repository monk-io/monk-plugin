package manifest

type Runnable struct {
	Name       string                `yaml:"name"`
	Containers map[string]*Container `yaml:"containers"`
	Services   map[string]*Service   `yaml:"services"`
}

type Container struct {
	Image       string            `yaml:"image"`
	Command     []string          `yaml:"command,omitempty"`
	Environment []string          `yaml:"environment,omitempty"`
	Volumes     map[string]string `yaml:"volumes,omitempty"`
}

type Service struct {
	Container string `yaml:"container"`
	Port      int    `yaml:"port"`
	Protocol  string `yaml:"protocol"`
}
