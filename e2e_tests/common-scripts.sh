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

validate_and_get_firehose_stream_arn() {
  local stack_name=$1

  log "Retrieving Firehose stream ARN for stack: $stack_name"
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

  # Check firehose_stream_arn is not null
  if [ -z "$firehose_stream_arn" ] || [ "$firehose_stream_arn" == "None" ]; then
    exit_with_error "Failed to retrieve Firehose delivery stream ARN for physical ID: $firehose_stream_physical_id"
  fi

  echo "$firehose_stream_arn"
}

validate_stack_resources_with_subscription() {
  local stack_name=$1
  local log_group_name=$2
  local log_group_filter=$3

  log "Validating stack resources for stack: $stack_name"
  firehose_stream_arn=$(validate_and_get_firehose_stream_arn "$stack_name")

  subscriptions=$(aws logs describe-subscription-filters --log-group-name "$log_group_name" --query 'subscriptionFilters[*].[destinationArn, filterPattern]' --output text)

  # Check if the Firehose delivery stream is subscribed to the log group
  if echo "$subscriptions" | grep -q "$firehose_stream_arn"; then
    if [ -z "$log_group_filter" ] || [ "$log_group_filter" == "''" ]; then
      log "Firehose Delivery Stream $firehose_stream_arn is subscribed to log group: $log_group_name"
    elif echo "$subscriptions" | grep -q "$log_group_filter"; then
      log "Firehose Delivery Stream $firehose_stream_arn is subscribed to log group: $log_group_name with filter: $log_group_filter"
    else
      exit_with_error "Firehose Delivery Stream $firehose_stream_arn is not subscribed to log group: $log_group_name with filter: $log_group_filter"
    fi
  else
    exit_with_error "Firehose Delivery Stream $firehose_stream_arn is not subscribed to log group: $log_group_name"
  fi

}

validate_stack_resources_without_subscription() {
  local stack_name=$1

  log "Validating stack resources for stack: $stack_name"
  validate_and_get_firehose_stream_arn "$stack_name"

}


exit_with_error() {
  echo "Error: $1"
  exit 1
}