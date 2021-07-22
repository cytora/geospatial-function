package storage

import "context"

type Storage interface {
	CompanyData(ctx context.Context, crn string, groups []string) (*Data, error)
}
