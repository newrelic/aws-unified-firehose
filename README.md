# aws-unified-firehose
Forwards logs from cloudwatch to NewRelic through Amazon Data Firehose

## Features

- Collects logs from Amazon CloudWatch.
- Forwards logs to NewRelic using Amazon Data Firehose.
- Allows users to attach custom attributes to the logs to make it easier to search, filter, analyze, and parse the logs
- Scalable and reliable log forwarding.
- Stores license key in Secret Manager by default.

## Requirements

- SAM CLI - [Install the SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)

## Deployment

To try this integration out you can use the `sam` cli to deploy the cloudformation template (`firehose-template.yml`). Make sure **aws is properly authenticated with an account of your choice**.


#### CloudFormation Parameters

- `NewRelicRegion` : Can either be `US` or `EU` depending on which endpoint to be used to push logs to New Relic
  - For this param `US` is default
- `LicenseKey`: Used when forwarding logs to New Relic
- `LogGroupConfig` : String representation of JSON array of objects of your CloudWatch LogGroup(s) and respective filter (if applicable) to set the Lambda function trigger.
  - Example : ```[{"LogGroupName":"group1"}, {"LogGroupName":"group2", "FilterPattern":"ERROR"},  {"LogGroupName":"group3", "FilterPattern":"INFO"}]```
- `LoggingFirehoseStreamName` : Name of new Data Firehose Delivery Stream (must be unique per AWS account in the same AWS Region)
  - The default value will be `NewRelic-Logging-Delivery-Stream`
- `LoggingS3BackupBucketName`: S3 Bucket Destination for failed events (must be globally unique across all AWS accounts in all AWS Regions within a partition)
  - The default value will be `firehose-logging-backup`
- `EnableCloudWatchLoggingForFirehose`: Can either be `true` or `false` to enable CloudWatch logging for the Amazon Data Firehose stream. Enabling logging can help in troubleshooting issues in pushing data through firehose stream. `false` by default
- `NewRelicAccountId` : The New Relic Account ID to which the logs will be pushed
- `CommonAttributes` : Common attributes to be added to all logs. This should be a JSON object.
  - Example : ```[{"AttributeName": "name1", "AttributeValue": "value1"}, {"AttributeName": "name2", "AttributeValue": "value2}]```
- `StoreNRLicenseKeyInSecretManager` : Can either be `true` or `false` depending on which cloud formation stack decides whether to store your license key in the environment variables or to create a new secret in aws secrets manger.
  - For this param `true` is default

