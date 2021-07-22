package config

import (
	"os"
	"testing"

	conf "github.com/cytora/go-platform-utils/config"
	"github.com/stretchr/testify/assert"
)

func TestLoad(t *testing.T) {
	coreEnv := conf.CoreEnvLambda{
		Env:               "cytora-dev",
		AWSRegion:         "eu-west-1",
		MetricsClientPort: "8125",
		Port:              3000,
		Service:           "test",
	}
	tests := []struct {
		name    string
		want    *Config
		wantErr bool
		envs    map[string]string
	}{
		{
			name:    "fail local",
			wantErr: true,
			envs: map[string]string{
				"SERVICE":    "test",
				"ENV":        "cytora-dev",
				"LOCAL":      "XXX",
				"AWS_REGION": "eu-west-1",
			},
		},
		{
			name:    "fail not local",
			wantErr: true,
			envs: map[string]string{
				"SERVICE":    "test",
				"ENV":        "cytora-dev",
				"LOCAL":      "false",
				"AWS_REGION": "eu-west-1",
			},
		},
		{
			name: "is local",
			want: &Config{
				CoreEnvLambda: coreEnv,
				Local:         true,
			},
			envs: map[string]string{
				"SERVICE":    "test",
				"ENV":        "cytora-dev",
				"LOCAL":      "true",
				"AWS_REGION": "eu-west-1",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			os.Clearenv()
			for key, val := range tt.envs {
				os.Setenv(key, val)
				defer os.Unsetenv(key)
			}
			c, err := Load()
			if tt.wantErr && err == nil {
				assert.NotNil(t, err, "error expected")
			}
			assert.Equal(t, tt.want, c, "unexpected values")
		})
	}
}
