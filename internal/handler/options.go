package handler

import "github.com/cytora/geospatial-lambda/internal/storage"

type OptionFunc func(opt *Options)

type Options struct {
    storage storage.Storage // nolint
}

func defaultHandlerOptions() *Options {
	return &Options{}
}
