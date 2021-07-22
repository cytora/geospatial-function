#!/usr/bin/env bash

# Exit on first error
set -e

export GOPRIVATE="github.com/cytora"

CUR_DIR="$(pwd)"

print_help() {
  echo "usage: build.sh bi|fix|lint|test|help"
  echo "  bi      generate code from protobuf definition for BI messages"
  echo "  list            list all Go packages in this project"
  echo "  clean           delete build artifacts"
  echo "  download        download Go dependencies"
  echo "  fix             auto format Go source code and tidy go.sum for each sub module in this project"
  echo "  lint            lint each sub module in this project"
  echo "  test            run tests"
  echo "  circle-test     run tests that are only for CircleCI"
  echo "  build           build each submodule"
  echo "  help            print this message"
  echo ""
  echo "Make sure goimports and golangci-lint is installed, by running:"
  echo "    go get -u golang.org/x/tools/cmd/goimports"
  echo "    go get -u github.com/golangci/golangci-lint/cmd/golangci-lint"
  exit 1
}

list_packages() {
  list_functions
  list_component_tests
  list_internal
}

list_internal() {
  find ./internal -name '*.go' -print0 | xargs -0 -n1 dirname | sort --unique
}

list_functions() {
  find ./functions -name 'main.go' -print0 | xargs -0 -n1 dirname
}

list_component_tests() {
  find ./component-tests -name 'main.go' -o -name 'main_test.go' -print0 | xargs -0 -n1 dirname
}


clean() {
  echo "Cleaning ..."
  rm -rf "${CUR_DIR:?}"/bin/* dist.zip
  echo "Cleaned"
}

build() {
  mkdir -p "${CUR_DIR}/bin"

  echo "Building functions ..."
  for d in $(list_functions | cut -f3 -d '/'); do
    echo "Building function $d ..."
    cd "functions/${d}"
    GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o "${CUR_DIR}/bin/$d" .
    echo "Built function $d"
    cd "$CUR_DIR"
  done

  echo "Building component tests..."
  for d in $(list_component_tests | cut -f3 -d '/'); do
    echo "Building component test $d ..."
    cd "component-tests/${d}"
    GOOS=linux GOARCH=amd64 go test -c -o "../../bin/${d}ComponentTest" .
    echo "Built component test $d"
    cd "$CUR_DIR"
  done

  chmod a+x "${CUR_DIR}"/bin/*

  zip -r dist.zip bin
}

unit_test() {
      go test -cover -count=1 -v "./internal/..."

}
list_dirs() {
  # Don't forget root
  echo '.'
  find . -name '*.go' -print0 | xargs -0 -n1 dirname | sort --unique | grep -v vendor
}

fix() {
  echo "Fixing imports ..."
  goimports -l -w $(list_dirs)
  echo "Tidying go.sum ..."
  for d in $(list_dirs); do
    echo "Tidying directory $d ..."
    cd "$d"
    go mod tidy
    cd "$CUR_DIR"
  done
}

lint() {
  echo "Linting subpackages ..."
  go mod tidy
  for d in $(list_packages); do
    echo "Linting directory $d ..."
    golangci-lint run "$d"
  done
}

test() {
  echo "unit tests"
  for d in $(list_functions); do
    echo "Testing directory $d ..."
    go test -cover -count=1 "$d/..."
  done
}

# For CircleCI only
circle_test() {
  echo "Testing subpackages ..."
  for d in $(list_functions); do
    echo "Testing directory $d ..."
    go test -cover -count=1 -tags circle "$d/..."
  done
}

bi() {
    echo "Fetching the latest protorepo-events ..."
    mkdir -p tmp
    cd tmp
    if cd protorepo-events; then
        git pull -q;
    else
        echo "Cloning protorepo-events ..."
        git clone -q git@github.com:cytora/protorepo-events.git;
    fi
    echo "Generating code from proto files ..."
    cd "$CUR_DIR"
    mkdir -p generated/proto
    pushd "$CUR_DIR"
    cd tmp/protorepo-events
    protos=$(find ./services/uwp-submissions/v4_0 -name '*.proto')
    protoc -I. \
      --go_out=paths=source_relative:../../generated/proto $protos
    popd
    echo "Finished"
}

case "$1" in
help)
  print_help
  ;;
list)
  list_packages
  ;;
clean)
  clean
  ;;
download)
  go mod download
  ;;
fix)
  fix
  ;;
lint)
  lint
  ;;
test)
  test
  ;;
circle-test)
  circle_test
  ;;
build)
  build
  ;;
bi)
  bi
  ;;
*)
  print_help
  ;;
esac

exit 0

go_test() {
    go test ./... -coverprofile test-coverage.out
}
