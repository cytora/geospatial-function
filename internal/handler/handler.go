package handler

import (
	"github.com/cytora/geospatial-lambda/internal/storage"
	"github.com/go-playground/validator"
)

type Handler struct {
	validator *validator.Validate
	storage   storage.Storage
}

func New(storage storage.Storage, opts ...OptionFunc) *Handler {
	opt := defaultHandlerOptions()
	for _, f := range opts {
		f(opt)
	}
	return &Handler{
		validator: validator.New(),
		storage:   storage,
	}
}
