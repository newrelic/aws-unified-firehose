# Building and deploying the changes
BASE_NAME=$(basename "$TEMPLATE_FILE_NAME" .yaml)
BUILD_DIR="$BASE_NAME"

# Build and package the SAM template
echo "Finding the version in version.yaml"
version=$(grep 'instrumentation_version' ../version.yaml | cut -d '"' -f2)
echo "Version found is: $version"
sed -i "s/\"instrumentation.version\", \"AttributeValue\": \"[^\"]*\"/\"instrumentation.version\", \"AttributeValue\": \"$version\"/" ../$TEMPLATE_FILE_NAME
sam build --template-file "../$TEMPLATE_FILE_NAME" --build-dir "$BUILD_DIR"
sam package --s3-bucket "$S3_BUCKET" --template-file "$BUILD_DIR/template.yaml" --output-template-file "$BUILD_DIR/$TEMPLATE_FILE_NAME"