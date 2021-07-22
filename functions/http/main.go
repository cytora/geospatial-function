package main

import (
	"net/http"

	"github.com/cytora/go-platform-utils/logging"
	"github.com/cytora/go-platform-utils/server"

	"github.com/cytora/geospatial-lambda/internal"
	"github.com/cytora/geospatial-lambda/internal/config"
	"github.com/cytora/geospatial-lambda/internal/handler"
	"github.com/cytora/geospatial-lambda/internal/storage/pg"
)

var (
	configs *config.Config
)

func init() {
	var err error
	configs, err = config.Load()
	if err != nil {
		logging.FatalNoCtx(err, nil, "failed to load configuration")
	}

}

func main() {
	srv, err := server.NewLambdaServer(configs.Env, configs.Service, configs.Version)
	if err != nil {
		logging.FatalNoCtx(err, nil, "failed to create lambda server")
	}
	stg, err := pg.New(configs)
	if err != nil {
		logging.FatalNoCtx(err, nil, "failed to start storage connection")
	}
	h := handler.New(stg)
	srv.MustAddRoute(server.RouteOption{
		API:    internal.CompanyDataEndpoint,
		Method: http.MethodGet,
		Path:   "/v2/company/{crn}",
	}, server.ToHTTPHandlerFunc(h.Retrieve))
	srv.Run()
}
