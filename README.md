# aws-unified-firehose
Forwards logs from cloudwatch to NewRelic through AWS firehose

## Features

- Collects logs from AWS CloudWatch.
- Forwards logs to NewRelic using AWS Firehose.
- Allows users to attach custom attributes to the logs to make it easier to search, filter, analyze, and parse the logs
- Scalable and reliable log forwarding.

## Requirements

- AWS CLI already configured with Administrator permission
- [Docker installed](https://www.docker.com/community-edition)
- SAM CLI - [Install the SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)

## Deployment

To try this lambda out you can use the `sam` cli to deploy the CFT (`firehose-template.yml`). Make sure **aws is properly authenticated with an account of your choice**.


#### CloudFormation Parameters

- `NewRelicRegion` : Can either be `US` or `EU` depending on which endpoint to be used to push logs to New Relic
- `LicenseKey`: Used when forwarding logs to New Relic
- `LogGroupConfig` : String representation of JSON array of objects of your CloudWatch LogGroup(s) and respective filter (if applicable) to set the Lambda function trigger.
  - Example : ```[{"LogGroupName":"group1"}, {"LogGroupName":"group2", "FilterPattern":"ERROR"},  {"LogGroupName":"group3", "FilterPattern":"INFO"}]```
- `LoggingFirehoseStreamName` : Name of new Data Firehose Delivery Stream (must be unique per AWS account in the same AWS Region)
- `LoggingS3BackupBucketName`: S3 Bucket Destination for failed events (must be globally unique across all AWS accounts in all AWS Regions within a partition)
- `EnableCloudWatchLoggingForFirehose`: Can either be `true` or `false` to enable CloudWatch logging for the Firehose stream.
- `NewRelicAccountId` : The New Relic Account ID to which the logs will be pushed
- `CommonAttributes` : Common attributes to be added to all logs. This should be a JSON object.
  - Example : ```[{"AttributeName": "name1", "AttributeValue": "value1"}, {"AttributeName": "name2", "AttributeValue": "value2}]```
- `StoreNRLicenseKeyInSecretManager` : Can either be `true` or `false` depending on which cloud formation stack decides whether to store your license key in the environment variables or to create a new secret in aws secrets manger.

## Building and packaging
To build and package, follow these steps:
1. Authenticate with your aws account details
2. Create an S3 bucket with a unique name, e.g., `test123`.
3. Build the project:
    ```sh
    sam build -u --template-file firehose-template.yaml
    ```
4. The build will be located by default at `.aws-sam/build`, and a template file will be created with the name `template.yaml`.
5. Package the project:
    ```sh
    sam package --s3-bucket test123 --template-file .aws-sam/build/template.yaml --output-template-file firehose-template.yaml --region us-east-2
    ```
6. Copy the main template file to the S3 bucket:
    ```sh
    aws s3 cp .aws-sam/build/firehose-template.yaml s3://test123/firehose-template.yaml
    ```