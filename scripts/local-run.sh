#!/usr/bin/env bash

# Exit on first error
set -e

# Enable job control so background jobs can be controlled
set -m

AWS_REGION="eu-west-1"
ENV="local"

# If CUR_DIR is /root/path/to/my-awesome-function, SERVICE=my-awesome
SERVICE="${CUR_DIR##*/}"
SERVICE="${SERVICE%-*}"
BUILD="123"

CUR_DIR="$(pwd)"

# Get env var from env.sh, if available
if [[ -f env.sh ]]; then
  . env.sh
fi

#####################
# Template elements #
#####################
SAM_TEMPLATE=$(
  cat <<'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: >
  local-run
  Template for running HTTP functions locally
# More info about Globals: https://github.com/awslabs/serverless-application-model/blob/master/docs/globals.rst
Globals:
  Api:
    Cors:
      AllowMethods: "'*'"
      AllowHeaders: "'*'"
      AllowOrigin: "'*'"
  Function:
    Timeout: 20
Resources:
EOF
)

DOCKER_COMPOSE_TEMPLATE=$(
  cat <<EOF
version: "3"
services:
  localstack:
    image: localstack/localstack:latest
    environment:
      - DEFAULT_REGION=$AWS_REGION
      - SERVICES=dynamodb,sns,sqs,s3,lambda
      - DOCKER_HOST=unix:///var/run/docker.sock
      - DEBUG=1 
      - LAMBDA_EXECUTOR=docker-reuse
      - MAIN_CONTAINER_NAME=fd_localstack_1
    ports:
      - "4566:4566"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
EOF
)

LOCALSTACK_ENDPOINT="http://localhost:4566"

###########
# Helpers #
###########

# Input:
#   $1 = path to service-spec.yml
# Output:  All arrays have same length.  Only lambdas with "event.http.enabled == true" are output.
#   func_names: array of function name
#   func_handlers: array of function handler
#   func_paths: array of function path
#   func_method: array of function HTTP methods
list_http_functions() {
  local service_spec_file="$1"
  if [[ ! -e "$service_spec_file" ]]; then
    echo "Service specfile \"$service_spec_file\" not found"
  fi

  func_names=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.http.enabled==true).functionName'))
  func_handlers=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.http.enabled==true).functionSpec.handler'))
  func_paths=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.http.enabled==true).event.http.path'))
  func_methods=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.http.enabled==true).event.http.method'))
}

list_dynamo_stream_functions() {
  local service_spec_file="$1"
  if [[ ! -e "$service_spec_file" ]]; then
    echo "Service specfile \"$service_spec_file\" not found"
  fi

  dys_func_names=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.dynamodb.enabled==true).functionName'))
  dys_func_handlers=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.dynamodb.enabled==true).functionSpec.handler'))
  dys_func_event_sources=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.dynamodb.enabled==true).event.dynamodb.eventSource'))
  dys_func_batch_sizes=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.dynamodb.enabled==true).event.dynamodb.batchSize'))
  dys_func_starting_positions=($(cat "$service_spec_file" | yq r - 'spec.lambdas.(event.dynamodb.enabled==true).event.dynamodb.startingPosition'))
}

# Input:
#   $1 = path to env.sh
#   func_names
#   func_paths
#   func_methods
# Output:
#   stdout: template
create_sam_template() {
  local template="$SAM_TEMPLATE"
  local env_file="$1"
  if [[ ! -e "$env_file" ]]; then
    echo "Env vars file \"$env_file\" not found"
  fi
  # Local array variables
  declare -a env_var_keys
  declare -a env_var_values
  # Need to do this way so value with spaces are not split
  while IFS='' read -r value; do
    env_var_keys+=("$value")
  done <<<"$(sed -nE 's/^[[:blank:]]*export[[:blank:]]+([[:alnum:]_-]+)="?([^"]*)"?/\1/p' "$env_file")"
  while IFS='' read -r value; do
    env_var_values+=("$value")
  done <<<"$(sed -nE 's/^[[:blank:]]*export[[:blank:]]+([[:alnum:]_-]+)="?([^"]*)"?/\2/p' "$env_file")"
  # Populate environment variables in template
  for i in "${!env_var_keys[@]}"; do
    template="$(echo "$template" | yq w - "Globals.Function.Environment.Variables.${env_var_keys[$i]}" "${env_var_values[$i]}")"
  done
  # Populate functions
  for i in "${!func_names[@]}"; do
    # name converts my-good_function to MyGoodFunction
    local name="$(echo "${func_names[$i]}" | sed -E 's/(-|_)/ /g' | awk '{for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1' | sed -E 's/ //g')"
    local v="$(
      yq n "Resources.$name.Type" "AWS::Serverless::Function" |
        yq w - "Resources.$name.Properties.CodeUri" "dist.zip" |
        yq w - "Resources.$name.Properties.Handler" "${func_handlers[$i]}" |
        yq w - "Resources.$name.Properties.Runtime" "go1.x" |
        yq w - "Resources.$name.Properties.Tracing" "Active" |
        yq w - "Resources.$name.Properties.Events.CatchAll.Type" "Api" |
        yq w - "Resources.$name.Properties.Events.CatchAll.Properties.Path" "${func_paths[$i]}" |
        yq w - "Resources.$name.Properties.Events.CatchAll.Properties.Method" "${func_methods[$i]}"
    )"
    template="$(yq m <(echo "$template") <(echo "$v"))"
  done
  echo "$template"
}

# Input:
#   $1 = path to service-spec.yml
# Output:
#   0: if docker-compose is needed.  This means service-spec.yml specifies dynamo tables or SNS topics.
#   1: otherwise
need_docker_compose() {
  local service_spec_file="$1"
  if [[ ! -e "$service_spec_file" ]]; then
    echo "Service specfile \"$service_spec_file\" not found"
  fi

  if [[ "$(yq r "$service_spec_file" --length 'spec.databases')" -gt 0 ]]; then
    return 0
  fi

  if [[ "$(yq r "$service_spec_file" --length 'spec.topics')" -gt 0 ]]; then
    return 0
  fi

  if [[ "$(yq r "$service_spec_file" --length 'spec.buckets')" -gt 0 ]]; then
    return 0
  fi

  return 1
}

# Output:
#   1: if Dynamo, SNS, SQS or S3 isn't ready in Localstack
#   0: otherwise
check_aws_services_ready() {
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb list-tables 2>/dev/null 1>&2 || {
    echo "Dynamo not ready"
    return 1
  }
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" sns list-topics 2>/dev/null 1>&2 || {
    echo "SNS not ready"
    return 1
  }
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" sqs list-queues 2>/dev/null 1>&2 || {
    echo "SQS not ready"
    return 1
  }
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" s3api list-buckets 2>/dev/null 1>&2 || {
    echo "S3 not ready"
    return 1
  }
  return 0
}

# Starts docker-compose in background mode, and also print logs in background.
start_docker_compose() {
  stop_docker_compose

  if [[ -f env.sh ]]; then
    . env.sh
  fi

  # Trap signals
  trap cleanup SIGINT

  docker-compose -f <(echo "$DOCKER_COMPOSE_TEMPLATE") up -d --remove-orphans
  # Print logs in background
  docker-compose -f <(echo "$DOCKER_COMPOSE_TEMPLATE") logs --no-color -f -t 1> >(color_output_dark_gray) 2>&1 || echo "stopped printing docker-compose logs" &
  # Wait for Localstack to become ready
  local counter=0
  while ! check_aws_services_ready && ((counter++ < 20)); do
    echo "Waiting for Localstack to become ready, retry $counter ..."
    sleep 1
  done
  if ! check_aws_services_ready; then
    echo "Localstack failed to become ready, stopping docker-compose ..."
    # Remove docker-compose
    stop_docker_compose
    echo "docker-compose stopped!"
    exit 1
  fi
  echo "docker-compose started!"
}

stop_docker_compose() {
  docker-compose -f <(echo "$DOCKER_COMPOSE_TEMPLATE") rm -f -s
}

# Input:
#   $1 = path to service-spec.yml
#   $2 = print|create
# Output:
#   If $2 == print, then only print out the AWS CLI input yaml file.
#   if $2 == create, then use AWS CLI to create tables.
parse_and_create_dynamo_tables() {
  local service_spec_file="$1"
  if [[ ! -e "$service_spec_file" ]]; then
    echo "Service specfile \"$service_spec_file\" not found"
  fi

  local table_names=($(cat "$service_spec_file" | yq r - --printMode v 'spec.databases[*].tableName'))
  for t_name in "${table_names[@]}"; do
    # Build create table template for AWS CLI.
    local table_spec="$(cat "$service_spec_file" | yq r - --printMode v "spec.databases.(tableName==$t_name).tableSpec")"
    local table_name="$(echo "$table_spec" | yq r - 'tableName')"
    local partition_key="$(echo "$table_spec" | yq r - 'partitionKey.name')"
    local partition_key_att_type="$(echo "$table_spec" | yq r - 'partitionKey.attributeType')"
    local sort_key="$(echo "$table_spec" | yq r - 'sortKey.name')"
    local sort_key_att_type="$(echo "$table_spec" | yq r - 'sortKey.attributeType')"
    local streamSpec="$(echo "$table_spec" | yq r - 'streamSpecification')"

    local create_table_tplt="$(
      yq n "TableName" "$ENV-$SERVICE-$table_name" |
        yq w - "KeySchema[+].AttributeName" "$partition_key" |
        yq w - "KeySchema[-1].KeyType" "HASH" |
        yq w - "AttributeDefinitions[+].AttributeName" "$partition_key" |
        yq w - "AttributeDefinitions[-1].AttributeType" "$partition_key_att_type" |
        yq w - "ProvisionedThroughput.ReadCapacityUnits" 10 |
        yq w - "ProvisionedThroughput.WriteCapacityUnits" 10 
    )"
    if [[ -n "$sort_key" ]]; then
      create_table_tplt="$(
        echo "$create_table_tplt" |
          yq w - "KeySchema[+].AttributeName" "$sort_key" |
          yq w - "KeySchema[-1].KeyType" "RANGE" |
          yq w - "AttributeDefinitions[+].AttributeName" "$sort_key" |
          yq w - "AttributeDefinitions[-1].AttributeType" "$sort_key_att_type"
      )"
    fi
    local attributes=("$partition_key" "$sort_key")
    local gsi_names=($(echo "$table_spec" | yq r - --printMode v 'secondaryIndexes[*].name'))
    for gsi_name in "${gsi_names[@]}"; do
      local gsi_primary_key="$(echo "$table_spec" | yq r - --printMode v "secondaryIndexes.(name==$gsi_name).primaryKey.name")"
      local gsi_primary_key_att_type="$(echo "$table_spec" | yq r - --printMode v "secondaryIndexes.(name==$gsi_name).primaryKey.attributeType")"
      local gsi_sort_key="$(echo "$table_spec" | yq r - --printMode v "secondaryIndexes.(name==$gsi_name).sortKey.name")"
      local gsi_sort_key_att_type="$(echo "$table_spec" | yq r - --printMode v "secondaryIndexes.(name==$gsi_name).sortKey.attributeType")"
      local gsi_projection="$(echo "$table_spec" | yq r - --printMode v "secondaryIndexes.(name==$gsi_name).projection.projectionType")"
      create_table_tplt="$(
        echo "$create_table_tplt" |
          yq w - "GlobalSecondaryIndexes[+].IndexName" "$gsi_name" |
          yq w - "GlobalSecondaryIndexes[-1].KeySchema[+].AttributeName" "$gsi_primary_key" |
          yq w - "GlobalSecondaryIndexes[-1].KeySchema[-1].KeyType" "HASH" |
          yq w - "GlobalSecondaryIndexes[-1].ProvisionedThroughput.ReadCapacityUnits" 10 |
          yq w - "GlobalSecondaryIndexes[-1].ProvisionedThroughput.WriteCapacityUnits" 10
      )"
      if [[ -n "$streamSpec" ]]; then
        create_table_tplt="$(
          echo "$create_table_tplt" |
            yq w - "StreamSpecification.StreamViewType" "$streamSpec" |
            yq w - "StreamSpecification.StreamEnabled" "true"
        )"
      fi
      if [[ -n "$gsi_projection" ]]; then
        create_table_tplt="$(
          echo "$create_table_tplt" |
            yq w - "GlobalSecondaryIndexes[-1].Projection.ProjectionType" "$gsi_projection"
        )"
      fi
      local pk_attr_present=false
      for attr in "${attributes[@]}"; do
        if [ "$attr" = "$gsi_primary_key" ]; then
          pk_attr_present=true
        fi
      done

      # Only add GSI's primary key if it isn't yet in AttributeDefinitions.
      if [ "$pk_attr_present" = false ]; then
        attributes+=("$gsi_primary_key")
        create_table_tplt="$(
          echo "$create_table_tplt" |
            yq w - "AttributeDefinitions[+].AttributeName" "$gsi_primary_key" |
            yq w - "AttributeDefinitions[-1].AttributeType" "$gsi_primary_key_att_type"
        )"
      fi
      if [[ -n "$gsi_sort_key" ]]; then
        create_table_tplt="$(
          echo "$create_table_tplt" |
            yq w - "GlobalSecondaryIndexes[-1].KeySchema[+].AttributeName" "$gsi_sort_key" |
            yq w - "GlobalSecondaryIndexes[-1].KeySchema[-1].KeyType" "RANGE"
        )"
      local sk_attr_present=false
      for attr in "${attributes[@]}"; do
        if [ "$attr" = "$gsi_sort_key" ]; then
          sk_attr_present=true
          # echo
        fi
      done

        # Only add GSI's sort key if it isn't yet in AttributeDefinitions.
        if [ "$sk_attr_present" = false ]; then
          attributes+=("$gsi_sort_key")
          create_table_tplt="$(
            echo "$create_table_tplt" |
              yq w - "AttributeDefinitions[+].AttributeName" "$gsi_sort_key" |
              yq w - "AttributeDefinitions[-1].AttributeType" "$gsi_sort_key_att_type"
          )"
        fi
      fi
    done

    case "$2" in
    print)
      echo "=== Dynamo table \"$t_name\" ==="
      echo "$create_table_tplt"
      echo
      ;;
    create)
      # Create table using AWS CLI
      # echo "Creating table \"$t_name\" ..." | color_output_cyan
      printf "Creating dynamodb table \"%s\" " "$t_name"
      # echo
      local table_output=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb create-table --cli-input-yaml "$create_table_tplt")
      if [ $? -ne 0 ]; then
        printf "\e[31m%s\e[m\n" "[ERR]"
      else
        printf "\e[36m%s \e[32m%s\e[m\n" "$(echo "$table_output" | jq -r ''.TableDescription.TableArn)" "[OK]"
        printf "Creating dynamodb stream \e[36m%s \e[32m%s\e[m\n" "$(echo "$table_output" | jq -r ''.TableDescription.LatestStreamArn)" "[OK]"
      fi                       
      ;;
    esac
  done
}

# Input:
#   $1 = path to service-spec.yml
#   $2 = print|create
# Output:
#   If $2 == print, then only print out the AWS CLI input yaml file.
#   if $2 == create, then use AWS CLI to create SNS topics and SQS queues.  Naming pattern see help message.
parse_and_create_sns() {
  local service_spec_file="$1"
  if [[ ! -e "$service_spec_file" ]]; then
    echo "Service specfile \"$service_spec_file\" not found"
  fi

  local sns_names=($(cat "$service_spec_file" | yq r - --printMode v 'spec.topics.(type==sns).name'))
  for sns_name in "${sns_names[@]}"; do
    local full_sns_name="$ENV-$AWS_REGION-$SERVICE-$sns_name"
    local full_sqs_name="$ENV-$AWS_REGION-$SERVICE-$sns_name-$BUILD"
    local sns_arn="arn:aws:sns:$AWS_REGION:000000000000:$full_sns_name"
    local sqs_arn="arn:aws:sqs:$AWS_REGION:000000000000:$full_sqs_name"
    case "$2" in
    print)
      echo "=== SNS topic \"$sns_name\" ==="
      echo "SNS ARN = $sns_arn"
      echo "SQS URL = http://localhost:4576/queue/$full_sqs_name"
      echo "SQS ARN = $sqs_arn"
      echo
      ;;
    create)
      # Create SNS and SQS using AWS CLI
      printf "Creating SNS topic \"%s\": " "$sns_name"
      local sns_topic=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" sns create-topic --name "$full_sns_name")
      if [ $? -ne 0 ]; then
        printf "\e[32m%s\e[m\n" "[ERR]"
      else
        printf "\e[36m%s \e[32m%s\e[m\n" "$(echo "$sns_topic" | jq -r '.TopicArn')" "[OK]"
      fi
      printf "Creating SQS queue \"%s\" " "$sns_name"
      local sqs_queue=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" sqs create-queue --queue-name "$full_sqs_name")
      if [ $? -ne 0 ]; then
        printf "\e[32m%s\e[m\n" "[ERR]"
      else
        printf "\e[36m%s \e[32m%s\e[m\n" "$(echo "$sqs_queue" | jq -r '.QueueUrl')" "[OK]"
      fi
      printf "Creating subscription \"%s\" " "$sns_name"
      local subscription=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" sns subscribe --protocol sqs --topic-arn "$sns_arn" --notification-endpoint "$sqs_arn")
      if [ $? -ne 0 ]; then
        printf "\e[32m%s\e[m\n" "[ERR]"
      else
        printf "\e[36m%s \e[32m%s\e[m\n" "$(echo "$subscription" | jq -r '.SubscriptionArn')" "[OK]"
      fi
      ;;
    esac
  done
}

# Input:
#   $1 = path to service-spec.yml
#   $2 = print|create
# Output:
#   If $2 == print, then only print out the AWS CLI input yaml file.
#   if $2 == create, then use AWS CLI to create S3 bucket.  Naming pattern see help message.
parse_and_create_s3() {
  local service_spec_file="$1"
  if [[ ! -e "$service_spec_file" ]]; then
    echo "Service specfile \"$service_spec_file\" not found"
  fi

  local bucket_names=($(cat "$service_spec_file" | yq r - --printMode v 'spec.buckets.(type==s3).name'))
  for bucket_name in "${bucket_names[@]}"; do
    local full_bucket_name="$ENV-$AWS_REGION-$SERVICE-$bucket_name"
    local bucket_arn="arn:aws:s3:::$full_bucket_name"
    case "$2" in
    print)
      echo "=== S3 bucket \"$bucket_name\" ==="
      echo "S3 BUCKET NAME = $full_bucket_name"
      echo "S3 BUCKET ARN = $bucket_arn"
      echo
      ;;
    create)
      # Create S3 using AWS CLI
      printf "Creating S3 bucket \"%s\" " "$bucket_name"
      local bucket=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" s3 mb "s3://$full_bucket_name")
      if [ $? -ne 0 ]; then
        printf "\e[32m%s\e[m\n" "[ERR]"
      else
        printf "\e[36m%s \e[32m%s\e[m\n" "$full_bucket_name" "[OK]"
      fi
      ;;
    esac
  done
}

# Input:
#   $1 = path to service-spec.yml
#   $2 = path to env file
parse_and_create_lambdas() {
  local service_spec_file="$1"
  local env_file="$2"
  local env_vars=$(sed -nE 's/^[[:blank:]]*export[[:blank:]]+([[:alnum:]_-]+)="?([^"]*)"?/\1=\2/p' "$env_file" | tr '\n' ',' | sed -nE 's/,$//p')
  list_dynamo_stream_functions $service_spec_file
  for i in "${!dys_func_names[@]}"; do
    local name="$(echo "${dys_func_names[$i]}" | sed -E 's/(-|_)/ /g' | awk '{for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1' | sed -E 's/ //g')"
    printf "Creating Lambda \"%s\" " "$name"
    local lambda=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda create-function \
                       --function-name "$name" \
                       --runtime "go1.x" \
                       --zip-file fileb://dist.zip \
                       --handler "${dys_func_handlers[$i]}" \
                       --environment "Variables={$env_vars}" \
                       --role local-role)
    if [ $? -ne 0 ]; then
      printf "\e[32m%s\e[m\n" "[ERR]"
    else
      printf "\e[36m%s \e[32m%s\e[m\n" "$(echo "$lambda" | jq -r '.FunctionArn')" "[OK]"
    fi                       
    streamArn=$(aws --endpoint-url=http://localhost:4566 dynamodb describe-table \
     --table-name "$ENV-$SERVICE-${dys_func_event_sources[$i]}" | jq '.Table.LatestStreamArn' -r)
    printf "Creating EventSourceMapping "
    local event_mapping=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda create-event-source-mapping \
                              --function-name "$name" \
                              --event-source $streamArn \
                              --batch-size  "${dys_func_batch_sizes[$i]}" \
                              --starting-position "${dys_func_starting_positions[$i]}")
    if [ $? -ne 0 ]; then
      printf "\e[31m%s\e[m\n" "[ERR]"
    else
      printf "\e[36m%s \e[32m%s\e[m\n" "$(echo "$event_mapping" | jq '.EventSourceArn + " => " + .FunctionArn' )" "[OK]"
    fi                       
  done
}

color_lambdas_output_light_blue() {
  while read line; do
    if [[ "$line" == *environment* ]] && [[ "$line" == *service* ]]; then
      printf '\e[1;34m%s\e[m\n' "$line"
    else
      echo "$line"
    fi
  done
}

color_output_dark_gray() {
  while read line; do
    printf '\e[90m%s\e[m\n' "$line"
  done
}

color_output_cyan() {
  while read line; do
    printf '\e[36m%s\e[m\n' "$line"
  done
}

color_output_green() {
  while read line; do
    printf '\e[32m%s\e[m\n' "$line"
  done
}

cleanup() {
  stop_docker_compose
  echo "docker-compose stopped!"
  exit 0
}

############
# Commands #
############

print_help() {
  echo "usage: local-run.sh [print|help]"
  echo "  [no arguments]  "
  echo "    [no flag]     calls SAM CLI to run HTTP functions locally.  Optionally runs docker-compose to launch Localstack, if service-spec.yml specifies Dynamo or SNS resources."
  echo "    --deps        optionally runs docker-compose to launch Localstack (in foreground), if service-spec.yml specifies Dynamo or SNS resources.  Useful to start deps only once."
  echo "    --sams        calls SAM CLI to run HTTP functions locally.  Useful if you only made code changes, so you don't need to restart the deps."
  echo "  stop            stop all background processes started by local-run.sh, in case they're not cleaned up properly."
  echo "  debug           print template yaml that will be used to call SAM and exit."
  echo "  help            print this message"
  echo
  echo 'There must be an "./env.sh" file, and environment variables (if any, if none the file can be empty) to Lambda functions must be defined in it, using export command.'
  echo
  echo 'This command assumes you have packaged your runnable into "./dist.zip".  This command reads "service-spec.yml", and does the following:'
  echo '* start docker-compose with Localstack and Redis.  Localstack has dynamo (port 4569), sns (port 4575), sqs (port 4576) services enabled and ports exposed on host.'
  echo '* read "databases", and create Dynamo tables in Localstack.'
  echo '* read "topics", and create SNS topics in Localstack.  Also creates an SQS subscribed to the SNS for testing.'
  echo '* read "lambdas" and find all "event.http" functions, and add them to SAM template.'
  echo '* run "sam local start-api" command with the SAM template.  This starts a local AWS gateway listening on port 3000.'
  echo
  echo 'Created AWS resources has the following properties:'
  echo '* Dynamo DB full name: $ENV-$SERVICE-$tableName'
  echo '* SNS ARN: arn:aws:sns:$AWS_REGION:000000000000:local-$AWS_REGION-$SERVICE-$topics.name'
  echo '* SQS ARN (this is the test SQS subscribed to the SNS topic): arn:aws:sqs:$AWS_REGION:000000000000:local-$AWS_REGION-$SERVICE-$topics.name-$BUILD'
  echo '* SQS URL (this is the test SQS subscribed to the SNS topic): http://localhost:4576/queue/local-$AWS_REGION-$SERVICE-$topics.name-$BUILD'
  echo '* S3 bucket ARN: arn:aws:s3:::local-$AWS_REGION-$SERVICE-$bucket_name'
  echo
  echo 'Stdout colors:'
  printf '\e[1;34m%s\e[m\n' 'Logs from your Lambda functions (when using "go-platform-utils/logging" package)'
  printf '\e[36m%s\e[m\n' 'Logs of this script'
  printf '\e[90m%s\e[m\n' 'Logs of this docker-compose'
  echo
  echo '==== Attention!!! ===='
  echo 'You should write your service to create the correct AWS session and user the correct resource names when running locally.  For examples check out https://github.com/cytora/platform-hello-function.'
  echo
  exit 1
}

# Checks if all necessary commands exist.
check_commands() {
  for CMD in "docker" "sam"; do
    if [[ -z "$(command -v $CMD)" ]]; then
      echo "Command \"$CMD\" not found, make sure it's installed" >&2
      exit 1
    fi
  done
  if [[ -z "$(command -v yq)" ]]; then
    echo 'Command "yq" not found, see https://mikefarah.gitbook.io/yq/ to install'
    exit 1
  fi
  if [[ "$(yq --version 2>&1 | sed -n -E -e 's|yq version ([[:digit:]]).*|\1|p')" -lt 3 ]]; then
    echo 'Command "yq" must have version >= 3'
    exit 1
  fi
  if [[ -z "$(command -v aws)" ]]; then
    echo 'Command "aws" not found, see https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html to install (make sure to install v2)'
    exit 1
  fi
  # Check version of AWS CLI
  if [[ "$(aws --version | sed -n -E -e 's|aws-cli/([[:digit:]]).*|\1|p')" -lt 2 ]]; then
    echo 'Command "aws" must have version >= 2'
    exit 1
  fi
  if [[ -z "$(command -v jq)" ]]; then
    echo 'Command "jq" not found, see https://stedolan.github.io/jq/download/ to install'
    exit 1
  fi
}

# Starts SAM and docker-compose locally.
# Input:
#   $1: if not set, starts both dependencies and SAM; if == "--deps", starts only dependencies; if == "--sam", starts only SAM.
start() {
  local mode="$1"
  check_commands
  if [[ ! -e "dist.zip" ]]; then
    echo "dist.zip does not exist, make sure you've built your code first"
    exit 1
  fi
  if [[ ! -e "env.sh" ]]; then
    echo "env.sh does not exist, make sure you create one (even if it's empty) and add it to .gitignore"
    exit 1
  fi
  # echo "cleaning tmp dir"
  # rm -fr /tmp/data/
  if [[ -z "$mode" ]] || [[ "$mode" == "--deps" ]]; then
    local ndc="$(
      need_docker_compose "${CUR_DIR}/service-spec.yml"
      echo $?
    )"
    if [[ "$ndc" -eq 0 ]]; then
      start_docker_compose
    fi
    parse_and_create_dynamo_tables "${CUR_DIR}/service-spec.yml" create
    parse_and_create_sns "${CUR_DIR}/service-spec.yml" create
    parse_and_create_s3 "${CUR_DIR}/service-spec.yml" create
    if [ "$WITH_EVENT_MAPPING" = "true" ]; then
      parse_and_create_lambdas "${CUR_DIR}/service-spec.yml" "${CUR_DIR}/env.sh" create
    else
      echo "not starting event mapping functions" | color_output_green
    fi
    echo "Dependencies started!"
    if [[ "$mode" == "--deps" ]]; then
      # Need to bring the background printing docker-compose logs job to foreground
      wait
    fi
  fi
  if [[ -z "$mode" ]] || [[ "$mode" == "--sam" ]]; then
    # Start SAM docker container and connect to host network, so it can use Localstack
    list_http_functions "${CUR_DIR}/service-spec.yml"
    local template="$(create_sam_template "${CUR_DIR}/env.sh")"
    local template_file=$(mktemp)
    echo "$template" > "$template_file"
    {
      sam local start-api -t "$template_file" -v "${CUR_DIR}" --docker-network host 2>&1 || echo "SAM local terminated"
    } | color_lambdas_output_light_blue
  fi
}

# Print template and exit.
print() {
  check_commands
  list_http_functions "${CUR_DIR}/service-spec.yml"
  echo "=== SAM template ==="
  create_sam_template "${CUR_DIR}/env.sh"
  echo
  parse_and_create_dynamo_tables "${CUR_DIR}/service-spec.yml" print
  parse_and_create_sns "${CUR_DIR}/service-spec.yml" print
  parse_and_create_s3 "${CUR_DIR}/service-spec.yml" print
}

case "$1" in
help)
  print_help
  ;;
debug)
  print
  ;;
stop)
  cleanup
  ;;
*)
  start "$@"
  ;;
esac

exit 0
