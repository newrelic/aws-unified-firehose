# Building and deploying the changes
BASE_NAME=$(basename "$TEMPLATE_FILE_NAME" .yaml)
BUILD_DIR="$BUILD_DIR_BASE/$BASE_NAME"

# Build and package the SAM template
sam build --template-file "../$TEMPLATE_FILE_NAME" --build-dir "$BUILD_DIR"
sam package --s3-bucket "$S3_BUCKET" --template-file "$BUILD_DIR/template.yaml" --output-template-file "$BUILD_DIR/$TEMPLATE_FILE_NAME"