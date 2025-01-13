#!/bin/bash

source config-file.cfg
source common-scripts.sh

# Test Case 1: 
# Create a Firehose stack without any subscription filter pattern
# Create a unique log message in CloudWatch Logs
# Validate the logs in New Relic
test_logs_without_filter_pattern() {
  local template_file=$1

cat <<EOF > log_group.json
'[{"LogGroupName":"$LOG_GROUP_NAME_1"}]'
EOF
LOG_GROUP_JSON=$(<log_group.json)

cat <<EOF > common_attribute.json
'[{"AttributeName":"$COMMON_ATTRIBUTE_KEY","AttributeValue":"$COMMON_ATTRIBUTE_VALUE"}]'
EOF
COMMON_ATTRIBUTES=$(<common_attribute.json)

  # Deploy the Firehose stack
  deploy_firehose_stack "$template_file" "$FIREHOSE_STACK_NAME_1" "$NEW_RELIC_LICENSE_KEY" "$NEW_RELIC_REGION" "$NEW_RELIC_ACCOUNT_ID" "true" "$LOG_GROUP_JSON" "$COMMON_ATTRIBUTES"
  
  # Validate the status of the Firehose stack
  validate_stack_deployment_status "$FIREHOSE_STACK_NAME_1"

  # Validate the stack resources

  validate_stack_resources "$FIREHOSE_STACK_NAME_1" "false" "$LOG_GROUP_NAME_1" ""
  # Generate a UUID and create a dynamic log message
  UUID=$(uuidgen)
  LOG_MESSAGE="RequestId: $UUID hello world"

  # Create a log event in CloudWatch Logs
  create_log_event "$LOG_GROUP_NAME_1" "$LOG_STREAM_NAME" "$LOG_MESSAGE"

  # Validate logs in New Relic
  validate_logs_in_new_relic "$NEW_RELIC_USER_KEY" "$NEW_RELIC_ACCOUNT_ID" "$LOG_MESSAGE" "true"

  # Delete the Firehose stack
  delete_stack "$FIREHOSE_STACK_NAME_1"
}

# Test Case 2: 
# Create a Firehose stack with a subscription filter pattern
# Create a unique log message with subscription filter pattern present in the log message
# Validate the logs in New Relic
# Create a unique log message without the subscription filter pattern
# Validate that the log message should not exist in New Relic

test_logs_with_filter_pattern() {
  local template_file=$1

cat <<EOF > log_group_filter.json
'[{"LogGroupName":"$LOG_GROUP_NAME_2","FilterPattern":"$LOG_GROUP_FILTER_PATTERN"}]'
EOF
LOG_GROUP_NAME_JSON=$(<log_group_filter.json)

cat <<EOF > common_attribute.json
'[{"AttributeName":"$COMMON_ATTRIBUTE_KEY","AttributeValue":"$COMMON_ATTRIBUTE_VALUE"}]'
EOF
COMMON_ATTRIBUTES=$(<common_attribute.json)

  # Deploy the Firehose stack
  deploy_firehose_stack "$template_file" "$FIREHOSE_STACK_NAME_2" "$NEW_RELIC_LICENSE_KEY" "$NEW_RELIC_REGION" "$NEW_RELIC_ACCOUNT_ID" "true" "$LOG_GROUP_NAME_JSON" "$COMMON_ATTRIBUTES"
  
  # Validate the status of the Firehose stack
  validate_stack_deployment_status "$FIREHOSE_STACK_NAME_2"

  # Validate the stack resources
  validate_stack_resources "$FIREHOSE_STACK_NAME_2" "false" "$LOG_GROUP_NAME_2" "$LOG_GROUP_FILTER_PATTERN"

  # Generate a UUID and create a dynamic log message with the filter pattern
  UUID=$(uuidgen)
  LOG_MESSAGE="RequestId: $UUID hello world $LOG_GROUP_FILTER_PATTERN"

  # Create a log event in CloudWatch Logs
  create_log_event "$LOG_GROUP_NAME_2" "$LOG_STREAM_NAME" "$LOG_MESSAGE"

  # Validate logs in New Relic (should exist)
  validate_logs_in_new_relic "$NEW_RELIC_USER_KEY" "$NEW_RELIC_ACCOUNT_ID" "$LOG_MESSAGE" "true"

  # Generate a UUID and create a dynamic log message without the filter pattern
  UUID=$(uuidgen)
  LOG_MESSAGE="RequestId: $UUID hello world"

  # Create a log event in CloudWatch Logs
  create_log_event "$LOG_GROUP_NAME_2" "$LOG_STREAM_NAME" "$LOG_MESSAGE"

  # Validate logs in New Relic (should not exist)
  validate_logs_in_new_relic "$NEW_RELIC_USER_KEY" "$NEW_RELIC_ACCOUNT_ID" "$LOG_MESSAGE" "false"

  # Delete the Firehose stack
  delete_stack "$FIREHOSE_STACK_NAME_2"
}

# Test Case 3: 
# Creating Firehose stack with Invalid Log Group Name 
# Validate that the Firehose stack is created successfully with Firehose delivery stream
test_logs_with_invalid_log_group() {
  local template_file=$1

cat <<EOF > invalid_log_group.json
'[{"LogGroupName":"$INVALID_LOG_GROUP_NAME"}]'
EOF
LOG_GROUP_INVALID_JSON=$(<invalid_log_group.json)

  # Deploy the Firehose stack
  deploy_firehose_stack "$template_file" "$FIREHOSE_STACK_NAME_3" "$NEW_RELIC_LICENSE_KEY" "$NEW_RELIC_REGION" "$NEW_RELIC_ACCOUNT_ID" "true" "$LOG_GROUP_INVALID_JSON" "''"
  
  # Validate the status of the Firehose stack
  validate_stack_deployment_status "$FIREHOSE_STACK_NAME_3"

  # Validate the stack resources
  validate_stack_resources "$FIREHOSE_STACK_NAME_3" "true" "''" "''"

  # Delete the Firehose stack
  delete_stack "$FIREHOSE_STACK_NAME_3"
}
  


BASE_NAME=$(basename "$TEMPLATE_FILE_NAME" .yaml)
BUILD_DIR="$BUILD_DIR_BASE/$BASE_NAME"


sam build --template-file "../$TEMPLATE_FILE_NAME" --build-dir "$BUILD_DIR"
sam package --s3-bucket "$S3_BUCKET" --template-file "$BUILD_DIR/template.yaml" --output-template-file "$BUILD_DIR/$TEMPLATE_FILE_NAME"

# Run Test Case 1: Logs without filter pattern
test_logs_without_filter_pattern  "$BUILD_DIR/$TEMPLATE_FILE_NAME" &
pid1=$!

# Run Test Case 2: Logs with filter pattern
test_logs_with_filter_pattern "$BUILD_DIR/$TEMPLATE_FILE_NAME" &
pid2=$!

# Run Test Case 3: Create stack with invalid log group
test_logs_with_invalid_log_group "$BUILD_DIR/$TEMPLATE_FILE_NAME" &
pid3=$!

# Check exit statuses of background jobs
if wait $pid1 && wait $pid2 && wait $pid3; then
  log "All tests passed successfully."
else
  exit_with_error "One or more tests failed."
fi
