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
    --capabilities CAPABILITY_IAM
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

  lambda_physical_id=$(aws cloudformation describe-stack-resources \
                  --stack-name "$stack_name" \
                  --logical-resource-id "$LAMBDA_LOGICAL_RESOURCE_ID" \
                  --query "StackResources[0].PhysicalResourceId" \
                  --output text
  )
  lambda_function_arn=$(aws lambda get-function --function-name "$lambda_physical_id" \
                  --query "Configuration.FunctionArn" \
                  --output text
  )

  subscriptions=$(aws logs describe-subscription-filters --log-group-name "$log_group_name" --query 'subscriptionFilters[*].[destinationArn, filterPattern]' --output text)

  if echo "$subscriptions" | grep -q "$lambda_function_arn" && echo "$subscriptions" | grep -q "$log_group_filter"; then
    echo "Lambda function $lambda_function_arn is subscribed to log group: $log_group_name with filter: $log_group_filter"
  else
    exit_with_error "Lambda function $lambda_function_arn is not subscribed to log group: $log_group_name"
  fi

}

exit_with_error() {
  echo "Error: $1"
  exit 1
}


BASE_NAME=$(basename "$TEMPLATE_FILE_NAME" .yaml)
BUILD_DIR="$BUILD_DIR_BASE/$BASE_NAME"

echo "Building and packaging the SAM template: $BASE_NAME"
echo "Building and packaging the SAM template: $BUILD_DIR"
echo pwd


sam build --template-file "../$TEMPLATE_FILE_NAME" --build-dir "$BUILD_DIR"
echo "build done packaging"
sam package --s3-bucket "$S3_BUCKET" --template-file "$BUILD_DIR/template.yaml" --output-template-file "$BUILD_DIR/$TEMPLATE_FILE_NAME"


cat <<EOF > parameter.json
'[{"LogGroupName":"$LOG_GROUP_NAME","FilterPattern":"$LOG_GROUP_FILTER_PATTERN"}]'
EOF
LOG_GROUP_NAMES=$(<parameter.json)

echo "Deploying the Firehose stack: $FIREHOSE_STACK_NAME"
deploy_firehose_stack "$BUILD_DIR/$TEMPLATE_FILE_NAME" "$FIREHOSE_STACK_NAME" "$NEW_RELIC_LICENSE_KEY" "$NEW_RELIC_REGION" "$NEW_RELIC_ACCOUNT_ID" "true" "$LOG_GROUP_NAMES" "''"

validate_stack_deployment_status "$FIREHOSE_STACK_NAME"

validate_stack_resources "$FIREHOSE_STACK_NAME" "$LOG_GROUP_NAME" "$LOG_GROUP_FILTER_PATTERN"

delete_stack "$FIREHOSE_STACK_NAME"




