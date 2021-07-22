package handler

import (
	"errors"
	"fmt"
)

// Error exported by the handler package
var (
	ErrHandler            = errors.New("handler error")
	ErrInvalidRequest     = fmt.Errorf("%w invalid request", ErrHandler)
	ErrInvalidQueryParams = fmt.Errorf("%w invalid query params", ErrHandler)
	ErrInternal           = fmt.Errorf("%w internal error", ErrHandler)
	ErrNotFound           = fmt.Errorf("%w not found", ErrHandler)
)
