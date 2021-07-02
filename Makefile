SHELL := /bin/bash
.PHONY: clean fix lint test circle-test build

default: clean lint circle-test build

env.sh:
	@echo "please create a env.sh file as per README" && false

clean:
	rm -frv bin/* dist.zip

download:
	@./scripts/build.sh download

fix:
	@./scripts/build.sh fix

lint:
	@./scripts/build.sh lint

test:
	@./scripts/build.sh test

unit-test:
	go test -cover -count=1 -v -coverprofile=test-coverage.out "./internal/..."

circle-test:
	@./scripts/build.sh circle-test

build: clean
	@./scripts/build.sh build

local-run: env.sh build
	@source env.sh && ./scripts/local-run.sh

local-run-deps: env.sh build
	@source env.sh && ./scripts/local-run.sh --deps

local-run-sam: env.sh build
	@source env.sh && ./scripts/local-run.sh --sam

local-test: env.sh
	@source ./env.sh; go test -timeout 20m -p=1 -count=1 -v ./component-tests/... | tee component-tests.log

local-stop:
	@./scripts/local-run.sh stop

local-debug:
	@./scripts/local-run.sh debug

concourse:
	platform-cli generate-concourse --config ./service-spec.yml > concourse.yml

pipeline:
	fly -t main set-pipeline -p geospatial-lambda -c concourse.yml --var SERVICE=geospatial-lambda
