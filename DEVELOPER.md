# AWS unified Firehose

Forwards logs from CloudWatch to New Relic via Amazon Kinesis Data Firehose.

## Requirements

- Install the AWS SAM CLI. Refer [SAM CLI Documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)

## Deployment

To try-out this integration, deploy the CloudFormation template (`firehose-template.yml`) using the `sam` CLI. Ensure AWS is authenticated with the desired account.


### Building and packaging

To build and package, follow these steps:

1. Authenticate with your AWS account details.
2. Create an S3 bucket with name. For example, `test123`.
3. To create the project build, run:

    ```sh
        sam build --template-file firehose-template.yaml
    ```

     **Note:** By default, build will be available at `.aws-sam/build` with the generated `template.yaml`

4. To package the build, run:

    ```sh
    sam package --s3-bucket test123 --template-file .aws-sam/build/template.yaml --output-template-file firehose-template.yaml --region us-east-2
    ```

5. Copy the main template file to the S3 bucket using:

    ```sh
    aws s3 cp .aws-sam/build/firehose-template.yaml s3://test123/firehose-template.yaml
    ```