package storage

import (
	"errors"
	"fmt"
)

var (
	ErrStorage       = errors.New("storage error")
	ErrInvalidGroups = fmt.Errorf("%w invalid groups", ErrStorage)
	ErrNotFound      = fmt.Errorf("%w not found", ErrStorage)
)
