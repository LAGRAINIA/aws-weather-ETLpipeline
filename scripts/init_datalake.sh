#!/bin/bash
set -e

BUCKET=$(terraform -chdir=terraform output -raw bucket_name)

if [ -z "$BUCKET" ]; then
    echo "ERROR: bucket_name not available from Terraform outputs"
    exit 1
fi

echo "Initializing datalake structure in s3://$BUCKET/"

PREFIXES=(
    "bronze/weather/"
    "silver/weather/"
    "gold/city_daily_stats/"
    "gold/weather_alerts_summary/"
    "gold/temperature_trends_weekly/"
    "scripts/"
    "athena-results/"
)

for prefix in "${PREFIXES[@]}"; do
    aws s3api put-object --bucket "$BUCKET" --key "$prefix" > /dev/null
    echo "  ✓ $prefix"
done

echo ""
echo "Datalake structure initialized."