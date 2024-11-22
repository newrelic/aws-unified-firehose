# aws-unified-firehose
Forwards logs from cloudwatch to NewRelic through Amazon Data Firehose

## Requirements

- SAM CLI - [Install the SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)

## Deployment

To try this integration out you can use the `sam` cli to deploy the cloudformation template (`firehose-template.yml`). Make sure **aws is properly authenticated with an account of your choice**.

## Building and packaging
To build and package, follow these steps:
1. Authenticate with your aws account details
2. Create an S3 bucket with a unique name, e.g., `test123`.
3. Build the project:
    ```sh
    sam build --template-file firehose-template.yaml
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