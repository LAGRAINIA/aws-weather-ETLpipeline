#!/bin/bash
set -e

BUCKET_NAME=$(terraform -chdir=terraform output -raw bucket_name)

echo "Uploading Glue scripts to s3://$BUCKET_NAME/scripts/"

aws s3 cp src/glue/bronze_to_silver.py s3://$BUCKET_NAME/scripts/
aws s3 cp src/glue/silver_to_gold.py s3://$BUCKET_NAME/scripts/

