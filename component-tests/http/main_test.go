package main

import (
	"fmt"
	"os"
	"testing"

	lt "github.com/cytora/go-platform-utils/lambdatesting"
)

func Test_mock(t *testing.T) {
	fmt.Println("no tests")
}

func TestMain(m *testing.M) {
	var opts []lt.RunnerOptsFunc
	if os.Getenv("ENV") == "local" {
		opts = append(opts, lt.WithLocalRunner())
	}
	runner := lt.NewRunner(m, opts...)
	runner.Run()
}
