#!/bin/bash

source config-file.cfg
source common-scripts.sh
source log_validation.sh

# Test Case 1: 
# Create a Firehose stack without any subscription filter pattern
# Create a unique log message in CloudWatch Logs
# Validate the logs in New Relic
test_logs_without_filter_pattern() {
  local template_file=$TEMPLATE_FILE_FULL_PATH

cat <<EOF > log_group.json
'[{"LogGroupName":"$LOG_GROUP_NAME_1"}]'
EOF
LOG_GROUP_JSON=$(<log_group.json)

cat <<EOF > common_attribute.json
'[{"AttributeName":"$COMMON_ATTRIBUTE_KEY","AttributeValue":"$COMMON_ATTRIBUTE_VALUE"}]'
EOF
COMMON_ATTRIBUTES=$(<common_attribute.json)

  delete_stack "$FIREHOSE_STACK_NAME_1"
}

# Test Case 2: 
# Create a Firehose stack with a subscription filter pattern
# Create a unique log message with subscription filter pattern present in the log message
# Validate the logs in New Relic
# Create a unique log message without the subscription filter pattern
# Validate that the log message should not exist in New Relic

test_logs_with_filter_pattern() {
  local template_file=$TEMPLATE_FILE_FULL_PATH

cat <<EOF > log_group_filter.json
'[{"LogGroupName":"$LOG_GROUP_NAME_2","FilterPattern":"$LOG_GROUP_FILTER_PATTERN"}]'
EOF
LOG_GROUP_NAME_JSON=$(<log_group_filter.json)

cat <<EOF > common_attribute.json
'[{"AttributeName":"$COMMON_ATTRIBUTE_KEY","AttributeValue":"$COMMON_ATTRIBUTE_VALUE"}]'
EOF
COMMON_ATTRIBUTES=$(<common_attribute.json)

 

  # Delete the Firehose stack
  delete_stack "$FIREHOSE_STACK_NAME_2"
}

# Test Case 3: 
# Creating Firehose stack with Invalid Log Group Name 
# Validate that the Firehose stack is created successfully with Firehose delivery stream
test_logs_with_invalid_log_group() {
  local template_file=$TEMPLATE_FILE_FULL_PATH

cat <<EOF > invalid_log_group.json
'[{"LogGroupName":"$INVALID_LOG_GROUP_NAME"}]'
EOF
LOG_GROUP_INVALID_JSON=$(<invalid_log_group.json)


  # Delete the Firehose stack
  delete_stack "$FIREHOSE_STACK_NAME_3"
}

test_with_store_secret_manager_false() {
  local template_file=$TEMPLATE_FILE_FULL_PATH

cat <<EOF > log_group.json
'[{"LogGroupName":"$LOG_GROUP_NAME_4"}]'
EOF
LOG_GROUP_JSON_4=$(<log_group.json)

cat <<EOF > common_attribute.json
'[{"AttributeName":"$COMMON_ATTRIBUTE_KEY","AttributeValue":"$COMMON_ATTRIBUTE_VALUE"}]'
EOF
COMMON_ATTRIBUTES=$(<common_attribute.json)

  # Delete the Firehose stack
  delete_stack "$FIREHOSE_STACK_NAME_4"
}

#Run the test cases
case $1 in
  test-without-filter)
    test_logs_without_filter_pattern 
    ;;
  test-with-filter)
    test_logs_with_filter_pattern 
    ;;
  test-with-invalid-log-group)
    test_logs_with_invalid_log_group 
    ;;
  test-with-secret-manager-false)
    test_with_store_secret_manager_false 
    ;;    
  *)
    echo "Invalid test case specified."
    exit 1
    ;;
esac
