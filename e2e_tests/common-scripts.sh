#!/bin/bash

source config-file.cfg

log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

deploy_firehose_stack() {
  local template_file=$1
  local stack_name=$2
  local license_key=$3
  local new_relic_region=$4
  local new_relic_account_id=$5
  local store_secret_in_secret_manager=$6
  local log_group_config=$7
  local common_attributes=$8

  log "Deploying Firehose stack: $stack_name"
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
  local stack_name=$1

  log "Validating stack deployment status for the stack : $stack_name"
  local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].StackStatus" --output text)
  if [[ "$stack_status" == "ROLLBACK_COMPLETE" || "$stack_status" == "ROLLBACK_FAILED" || "$stack_status" == "CREATE_FAILED"  || "$stack_status" == "UPDATE_FAILED" ]]; then
    log "Stack $stack_name failed to be created and rolled back."
    local failure_reason=$(aws cloudformation describe-stack-events --stack-name "$stack_name" --query "StackEvents[?ResourceStatus==\`$stack_status\`].ResourceStatusReason" --output text)
    exit_with_error "Stack $stack_name failed to be created. Failure reason: $failure_reason"
  else
    log "Stack $stack_name was created successfully."
  fi
}

delete_stack() {
  stack_name=$1

  log "Initiating deletion of stack: $stack_name"
  aws cloudformation delete-stack --stack-name "$stack_name"

  local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text)

  # delete stack with exponential back off retires with max cap of 5 minutes
  max_sleep_time=300  
  sleep_time=30
  while [[ $stack_status == "DELETE_IN_PROGRESS" ]]; do
    log "Stack $stack_name is still being deleted..."
    sleep $sleep_time
    if (( sleep_time < max_sleep_time )); then
      sleep_time=$(( sleep_time * 2 ))
    fi
    stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)
  done

  if [ -z "$stack_status" ]; then
    log "Stack $stack_name has been successfully deleted."
  elif [ "$stack_status" == "DELETE_FAILED" ]; then
    log "Failed to delete stack $stack_name."
  else
    log "Unexpected stack status: $stack_status."
  fi
}

validate_stack_resources() {
  local stack_name=$1
  local validate_only_firehose_stack=$2
  local log_group_name=$3
  local log_group_filter=$4


  log "Validating stack resources for stack: $stack_name"
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

  # Check firehose_stream_arn is not null before checking subscriptions
  if [ -z "$firehose_stream_arn" ] || [ "$firehose_stream_arn" == "None" ]; then
    exit_with_error "Failed to retrieve Firehose delivery stream ARN for physical ID: $firehose_stream_physical_id"
  fi

  # Skip log group subscription validation if validate_only_firehose_stack is true or log_group_filter is empty
  if [ "$validate_only_firehose_stack" == "true" ] || [ -z "$log_group_filter" ]; then
    log "Validated Firehose Stream, skipping log group subscription validation."
    return
  fi

  subscriptions=$(aws logs describe-subscription-filters --log-group-name "$log_group_name" --query 'subscriptionFilters[*].[destinationArn, filterPattern]' --output text)

  # Check if the Firehose delivery stream is subscribed to the log group with the specified filter pattern
  if echo "$subscriptions" | grep -q "$firehose_stream_arn" && echo "$subscriptions" | grep -q "$log_group_filter"; then
    log "Firehose Delivery Stream $firehose_stream_arn is subscribed to log group: $log_group_name with filter: $log_group_filter"
  else
    exit_with_error "Firehose Delivery Stream $firehose_stream_arn is not subscribed to log group: $log_group_name"
  fi

}


exit_with_error() {
  echo "Error: $1"
  exit 1
}

create_log_event() {
  local log_group_name=$1
  local log_stream_name=$2
  local log_message=$3

  log "Creating log event in CloudWatch Log Group: $log_group_name"
  local log_stream_exists=$(aws logs describe-log-streams --log-group-name "$log_group_name" --log-stream-name-prefix "$log_stream_name" --query "logStreams[?logStreamName=='$log_stream_name'] | length(@)" --output text)

  if [ "$log_stream_exists" -eq 0 ]; then
    log "Creating log stream: $log_stream_name"
    aws logs create-log-stream --log-group-name "$log_group_name" --log-stream-name "$log_stream_name"
  fi

  # Get the current timestamp in milliseconds
  timestamp=$(($(date +%s) * 1000 + $(date +%N) / 1000000))

  # Put log event
  aws logs put-log-events \
    --log-group-name "$log_group_name" \
    --log-stream-name "$log_stream_name" \
    --log-events timestamp=$timestamp,message="$log_message"

  log "Log event created successfully."

}

validate_logs_in_new_relic() {
  local user_key=$1
  local account_id=$2
  local log_message=$3
  local common_attributes=$4
  local should_log_exist=$5

  local nrql_query="SELECT * FROM Log WHERE message LIKE '%$log_message%' SINCE 10 minutes ago"
  local query='{"query":"query($id: Int!, $nrql: Nrql!) { actor { account(id: $id) { nrql(query: $nrql) { results } } } }","variables":{"id":'$account_id',"nrql":"'$nrql_query'"}}'

  local log_message_exists=false

  sleep_time=$SLEEP_TIME

  for i in {1..5}; do
    local response=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "API-Key: $user_key" \
      -d "$query" \
      https://api.newrelic.com/graphql)

    if echo "$response" | grep -q "$log_message"; then
      log "Log event successfully found in New Relic."
      log_message_exists=true
      validate_logs_meta_data "$response" "$common_attributes"
      break
    else
      log "Log event not found in New Relic. Retrying in $sleep_time seconds..."
      sleep $sleep_time
      sleep_time=$(( sleep_time * 2 ))
    fi
  done

  if [ "$should_log_exist" == "true" ] && [ "$log_message_exists" == "false" ]; then
    exit_with_error "Log event not found in New Relic after 10 retries."
  elif [ "$should_log_exist" == "false" ] && [ "$log_message_exists" == "true" ]; then
    exit_with_error "Log event should not exist in New Relic, but it was found."
  fi

}

validate_logs_meta_data (){
  local response=$1
  local common_attributes=$2

  # Remove single quotes from common_attributes
  common_attributes=$(echo "$common_attributes" | sed "s/'//g")

  # Validate common attributes
  for attribute in $(echo "$common_attributes" | jq -c '.[]'); do
    attribute_name=$(echo "$attribute" | jq -r '.AttributeName')
    attribute_value=$(echo "$attribute" | jq -r '.AttributeValue')
    if ! echo "$response" | grep -q "\"$attribute_name\":\"$attribute_value\""; then
      exit_with_error "Common attribute $attribute_name with value $attribute_value not found in New Relic logs."
    fi
  done
  log "Common attributes validated successfully."

  # Read default attributes from config file and replace underscores with dots
  while IFS='=' read -r key value; do
    if [[ $key == instrumentation_* ]]; then
      new_key=$(echo "$key" | sed 's/_/./g')
      if ! echo "$response" | grep -q "\"$new_key\":\"$value\""; then
        exit_with_error "Entity synthesis attribute $new_key with value $value not found in New Relic logs."
      fi
    fi
  done < config-file.cfg

  log "Entity synthesis parameter validated successfully."
}