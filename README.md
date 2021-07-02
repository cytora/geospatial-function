# geospatial-lambda

This service aims to provide Geospatial Functionality on top of RDS PostgreSQL/PostGIS. The API provides basic
discovery endpoint on top of registered geospatial layers as well as intersect endpoint for intersect given Lat, Lon
specific layer defined by name

## Setup
The team recommends installing [Homebrew](https://brew.sh/) or another package manager
if possible for easier installation and upgrade management.

The project requires has a few dependencies which need to be installed for local setup:
1. `go` - can be installed using `brew install go`
1. `golangci-lint`- install using package manager e.g. `brew install golangci-lint`
1. `awscli, aws-sam-cli` - install using package manager e.g. `brew tap aws/tap && brew install awscli aws-sam-cli`
1. `yq` - install using package manager e.g. `brew install yq`
