#!/bin/bash
set -e

BUCKET=$(terraform -chdir=terraform output -raw bucket_name)

if [ -z "$BUCKET" ]; then
    echo "ERROR: bucket_name not available from Terraform outputs"
    exit 1
fi

echo "Uploading Glue scripts to s3://$BUCKET/scripts/"

aws s3 cp src/glue/bronze_to_silver.py s3://$BUCKET/scripts/
aws s3 cp src/glue/silver_to_gold.py s3://$BUCKET/scripts/

echo ""
echo "Done."