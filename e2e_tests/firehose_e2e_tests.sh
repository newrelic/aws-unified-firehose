#!/bin/bash

source config-file.cfg
source common-scripts.sh
source log_validation.sh

# Test Case 1: 
# Create a Firehose stack without any subscription filter pattern
# Create a unique log message in CloudWatch Logs
# Validate the logs in New Relic
delete-stack() {
  delete_stack "$FIREHOSE_STACK_NAME_1"
  delete_stack "$FIREHOSE_STACK_NAME_2"
  delete_stack "$FIREHOSE_STACK_NAME_3"
  delete_stack "$FIREHOSE_STACK_NAME_4"
}

#Run the test cases
case $1 in
  delete-stack)
    delete-stack
    ;;
  *)
    echo "Invalid test case specified."
    exit 1
    ;;
esac
