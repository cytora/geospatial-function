package config

import (
	"context"
	"os"
	"strconv"

	"github.com/cytora/go-platform-utils/config"
	"github.com/cytora/go-platform-utils/logging"
)

type Config struct {
	config.CoreEnvLambda
	Local            bool   `envconfig:"LOCAL"`
	RDSProxyEndpoint string `envconfig:"RDS_PROXY_ENDPOINT"`
	RDSProxyUser     string `envconfig:"RDS_PROXY_USER"`
	RDSDBName        string `envconfig:"RDS_DB_NAME"`
}

func Load() (*Config, error) {
	c := &Config{}
	if val, present := os.LookupEnv("LOCAL"); present {
		var local bool
		var err error
		if local, err = strconv.ParseBool(val); err != nil {
			logging.Error(context.Background(), err, nil, "failed to load configuration")
			return nil, err
		}
		c.Local = local
	}
	var opts []config.OptionFunc
	if c.Local {
		localOpts := []config.OptionFunc{config.WithNoVaultClient(), config.WithNoSecretsManagerClient()}
		opts = append(opts, localOpts...)
	}
	if err := config.Populate(c, opts...); err != nil {
		logging.Error(context.Background(), err, logging.Data{"local": c.Local}, "failed to populate config")
		return nil, err
	}
	return c, nil
}
