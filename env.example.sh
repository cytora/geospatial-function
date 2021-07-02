# to connect to other service on dev, we need to provide cytora-dev
export ENV=cytora-dev

# to conenct to other services on dev, we need the dev auth key here (DON'T CHECK THIS FILE INTO GITHUB!!!!)
export AUTH_KEY=__AUTH_KEY_HERE__

# This triggers the local configuration of the function. It will connect to local dynamo, and skip getting secres from secret manager
export LOCAL=true

# this is where all cytora infrastructure runs. Not sure if it's required for this script.
export AWS_REGION=eu-west-1

# the service name
export SERVICE="geospatial-lambda"

# LocalStack edge endpoint
export LOCALSTACK_ENDPOINT="http://localhost:4566"

# Disables xray while running the code locally
export AWS_XRAY_SDK_DISABLED="true"
