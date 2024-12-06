# AWS unified Firehose

Forwards logs from Amazon CloudWatch to New Relic via Amazon Kinesis Data Firehose.

## Features

- Collects logs from CloudWatch.
- Forwards logs to New Relic using Amazon Kinesis Data Firehose.
- Enables users to attach custom attributes to logs. This will allows users to easily search, filter, analyze, and parse the logs.
- Offers scalable and reliable log forwarding.
- Stores the license key in Secrets Manager by default.

## Requirements

- Install the AWS SAM CLI. Refer [SAM CLI Documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)

## Deployment

To try-out this integration, deploy the CloudFormation template (`firehose-template.yml`) using the `sam` CLI. Ensure that the AWS is authenticated with the desired account.


### CloudFormation Parameters

| Parameter                              | Description |
|----------------------------------------|-------------|
| `NewRelicRegion`                       | The New Relic region (`US` or `EU`) for log forwarding. The default value is `US`. |
| `LicenseKey`                           | Your New Relic license key for log forwarding. |
| `LogGroupConfig`                       | A JSON array defining CloudWatch LogGroups and filters to set triggers for the Lambda function. For example: `[{"LogGroupName":"group1"}, {"LogGroupName":"group2", "FilterPattern":"ERROR"}, {"LogGroupName":"group3", "FilterPattern":"INFO"}]` |
| `LoggingFirehoseStreamName`            | Unique name for the Data Firehose Delivery Stream. The default value is `NewRelic-Logging-Delivery-Stream` |
| `LoggingS3BackupBucketName`            | Unique name for S3 bucket for backup of failed events. This name must be globally unique. The default value is `firehose-logging-backup` |
| `EnableCloudWatchLoggingForFirehose`   | CloudWatch logging for the Amazon Data Firehose stream. Enabling this can help you to troubleshoot issues in firehose stream. .The default value is `false` |
| `NewRelicAccountId`                    | The New Relic account ID to push the log. |
| `CommonAttributes`                     | JSON object of common attributes to add to all logs. For example: `[{"AttributeName": "name1", "AttributeValue": "value1"}, {"AttributeName": "name2", "AttributeValue": "value2"}]` |
| `StoreNRLicenseKeyInSecretManager`     | Determines if the license key is stored in AWS Secrets Manager (`true`) or environment variables (`false`). The default value is `true`. |