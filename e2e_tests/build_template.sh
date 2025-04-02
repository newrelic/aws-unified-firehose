# Building and deploying the changes
BASE_NAME=$(basename "$TEMPLATE_FILE_NAME" .yaml)
BUILD_DIR="$BASE_NAME"

# Build and package the SAM template
pwd
cat ../$TEMPLATE_FILE_NAME
pwd
echo "Building and packaging the SAM template"
echo $BASE_NAME
echo $BUILD_DIR
echo "Building and packaging the SAM template"
version=$(grep 'instrumentation_version' ../version.yaml | cut -d '"' -f2)
echo "Version: $version"
echo "Building and packaging the SAM template with version: $version"
sed -i "s/\"instrumentation.version\", \"AttributeValue\": \"[^\"]*\"/\"instrumentation.version\", \"AttributeValue\": \"$version\"/" ../$TEMPLATE_FILE_NAME
cat ../$TEMPLATE_FILE_NAME
echo "Building and packaging the SAM template with version hrai"
sam build --template-file "../$TEMPLATE_FILE_NAME" --build-dir "$BUILD_DIR"
cat "$BUILD_DIR/$TEMPLATE_FILE_NAME"
sam package --s3-bucket "$S3_BUCKET" --template-file "$BUILD_DIR/template.yaml" --output-template-file "$BUILD_DIR/$TEMPLATE_FILE_NAME"
cat "$BUILD_DIR/$TEMPLATE_FILE_NAME"