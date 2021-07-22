package mock

import (
	"context"
	"errors"

	"github.com/cytora/geospatial-lambda/internal/storage"
)

type StorageMock struct {
	Results *storage.Data
	Err     error

	IsCalled         bool
	CalledWithCRN    string
	CalledWithGroups []string
}

func (s *StorageMock) CompanyData(ctx context.Context, crn string, groups []string) (*storage.Data, error) {
	if s.Results == nil && s.Err == nil {
		return nil, errors.New("mock not configured")
	}
	s.IsCalled = true
	s.CalledWithCRN = crn
	s.CalledWithGroups = groups
	return s.Results, s.Err
}
