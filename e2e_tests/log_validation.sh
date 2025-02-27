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

  # Get the current timestamp
  timestamp=$(date +%s000)

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
  max_attempts=5

  for ((i=1; i<=max_attempts; i++)); do
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
    exit_with_error "Log event not found in New Relic after 5 retries."
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
  done < entity_synthesis_param.cfg

  log "Entity synthesis parameter validated successfully."
}