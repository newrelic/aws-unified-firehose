#!/bin/bash

source config-file.cfg

deploy_firehose_stack() {
  template_file=$1
  stack_name=$2
  license_key=$3
  new_relic_region=$4
  new_relic_account_id=$5
  store_secret_in_secret_manager=$6
  log_group_config=$7
  common_attributes=$8

  sam deploy \
    --template-file "$template_file" \
    --stack-name "$stack_name" \
    --parameter-overrides \
      LicenseKey="$license_key" \
      NewRelicRegion="$new_relic_region" \
      NewRelicAccountId="$new_relic_account_id" \
      StoreNRLicenseKeyInSecretManager="$store_secret_in_secret_manager" \
      LogGroupConfig="$log_group_config" \
      CommonAttributes="$common_attributes" \
    --capabilities CAPABILITY_NAMED_IAM

}

validate_stack_deployment_status() {
  stack_name=$1

  stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].StackStatus" --output text)
  if [[ "$stack_status" == "ROLLBACK_COMPLETE" || "$stack_status" == "ROLLBACK_FAILED" || "$stack_status" == "CREATE_FAILED"  || "$stack_status" == "UPDATE_FAILED" ]]; then
    echo "Stack $stack_name failed to be created and rolled back."
    failure_reason=$(aws cloudformation describe-stack-events --stack-name "$stack_name" --query "StackEvents[?ResourceStatus==\`$stack_status\`].ResourceStatusReason" --output text)
    exit_with_error "Stack $stack_name failed to be created. Failure reason: $failure_reason"
  else
    echo "Stack $stack_name was created successfully."
  fi
}

delete_stack() {
  stack_name=$1

  aws cloudformation delete-stack --stack-name "$stack_name"

  echo "Initiated deletion of stack: $stack_name"

  stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text)

  while [[ $stack_status == "DELETE_IN_PROGRESS" ]]; do
    echo "Stack $stack_name is still being deleted..."
    sleep 60
    stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)
  done

  if [ -z "$stack_status" ]; then
    echo "Stack $stack_name has been successfully deleted."
  elif [ "$stack_status" == "DELETE_FAILED" ]; then
    echo "Failed to delete stack $stack_name."
  else
    echo "Unexpected stack status: $stack_status."
  fi
}

validate_stack_resources() {
  stack_name=$1
  log_group_name=$2
  log_group_filter=$3

  firehose_stream_physical_id=$(aws cloudformation describe-stack-resources \
                  --stack-name "$stack_name" \
                  --logical-resource-id "$FIREHOSE_STREAM_LOGICAL_ID" \
                  --query "StackResources[0].PhysicalResourceId" \
                  --output text
  )

  # Get the ARN of the Firehose delivery stream using the physical ID
  firehose_stream_arn=$(aws firehose describe-delivery-stream \
                  --delivery-stream-name "$firehose_stream_physical_id" \
                  --query "DeliveryStreamDescription.DeliveryStreamARN" \
                  --output text
  )

  subscriptions=$(aws logs describe-subscription-filters --log-group-name "$log_group_name" --query 'subscriptionFilters[*].[destinationArn, filterPattern]' --output text)

  # Check firehose_stream_arn is not null before checking subscriptions
  if [ -z "$firehose_stream_arn" ] || [ "$firehose_stream_arn" == "None" ]; then
    exit_with_error "Failed to retrieve Firehose delivery stream ARN for physical ID: $firehose_stream_physical_id"
  fi

  # Check if the Firehose delivery stream is subscribed to the log group with the specified filter pattern
  if echo "$subscriptions" | grep -q "$firehose_stream_arn" && echo "$subscriptions" | grep -q "$log_group_filter"; then
    echo "Firehose Delivery Stream $firehose_stream_arn is subscribed to log group: $log_group_name with filter: $log_group_filter"
  else
    exit_with_error "Firehose Delivery Stream $firehose_stream_arn is not subscribed to log group: $log_group_name"
  fi

}

exit_with_error() {
  echo "Error: $1"
  exit 1
}

create_log_event() {
  echo "Creating log event in CloudWatch Log Group"
  log_group_name=$1
  log_stream_name=$2
  log_message=$3

  # Check if the log stream exists
  log_stream_exists=$(aws logs describe-log-streams --log-group-name "$log_group_name" --log-stream-name-prefix "$log_stream_name" --query "logStreams[?logStreamName=='$log_stream_name'] | length(@)" --output text)

  # Create a log stream
  if [ "$log_stream_exists" -eq 0 ]; then
    # Create a log stream if it does not exist
    aws logs create-log-stream --log-group-name "$log_group_name" --log-stream-name "$log_stream_name"
  fi

  # Get the current timestamp in milliseconds
  timestamp=$(($(date +%s) * 1000 + $(date +%N) / 1000000))

  # Put log event
  aws logs put-log-events \
    --log-group-name "$log_group_name" \
    --log-stream-name "$log_stream_name" \
    --log-events timestamp=$timestamp,message="$log_message"

  echo "Log event created successfully."

}

validate_logs_in_new_relic() {
  user_key=$1
  account_id=$2
  file_name=$3

  nrql_query="SELECT * FROM Log WHERE message LIKE '%$file_name%' SINCE 10 minutes ago"
  query='{"query":"query($id: Int!, $nrql: Nrql!) { actor { account(id: $id) { nrql(query: $nrql) { results } } } }","variables":{"id":'$account_id',"nrql":"'$nrql_query'"}}'

  for i in {1..10}; do
    response=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "API-Key: $user_key" \
      -d "$query" \
      https://api.newrelic.com/graphql)

    if echo "$response" | grep -q "$file_name"; then
      echo "Log event successfully found in New Relic."
      return 0
    else
      echo "Log event not found in New Relic. Retrying in 30 seconds... ($i/10)"
      sleep 30
    fi
  done

  exit_with_error "Log event not found in New Relic after 10 retries."
}



BASE_NAME=$(basename "$TEMPLATE_FILE_NAME" .yaml)
BUILD_DIR="$BUILD_DIR_BASE/$BASE_NAME"


sam build --template-file "../$TEMPLATE_FILE_NAME" --build-dir "$BUILD_DIR"
sam package --s3-bucket "$S3_BUCKET" --template-file "$BUILD_DIR/template.yaml" --output-template-file "$BUILD_DIR/$TEMPLATE_FILE_NAME"


cat <<EOF > parameter.json
'[{"LogGroupName":"$LOG_GROUP_NAME","FilterPattern":"$LOG_GROUP_FILTER_PATTERN"}]'
EOF
LOG_GROUP_NAMES=$(<parameter.json)

# Generate a random string to append to the default stack name
RANDOM_STRING=$(openssl rand -hex 4)
FIREHOSE_STACK_NAME="${DEFAULT_STACK_NAME}-${RANDOM_STRING}"

# Deploy the Firehose stack
deploy_firehose_stack "$BUILD_DIR/$TEMPLATE_FILE_NAME" "$FIREHOSE_STACK_NAME" "$NEW_RELIC_LICENSE_KEY" "$NEW_RELIC_REGION" "$NEW_RELIC_ACCOUNT_ID" "true" "$LOG_GROUP_NAMES" "''"

# Validate the status of the Firehose stack
validate_stack_deployment_status "$FIREHOSE_STACK_NAME"

# Validate the resources created by the Firehose stack
validate_stack_resources "$FIREHOSE_STACK_NAME" "$LOG_GROUP_NAME" "$LOG_GROUP_FILTER_PATTERN"

# Generate a UUID and create a dynamic log message
UUID=$(uuidgen)
LOG_MESSAGE="RequestId: $UUID hello world $LOG_GROUP_FILTER_PATTERN"

# Create a log event in CloudWatch Logs
create_log_event "$LOG_GROUP_NAME" "$LOG_STREAM_NAME" "$LOG_MESSAGE"

# Validate logs in New Relic
validate_logs_in_new_relic "$NEW_RELIC_USER_KEY" "$NEW_RELIC_ACCOUNT_ID" "$LOG_MESSAGE"

# Delete the Firehose stack
delete_stack "$FIREHOSE_STACK_NAME"