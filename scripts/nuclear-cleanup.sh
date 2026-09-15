#!/bin/bash
# nuclear-cleanup.sh — deletes ALL weather pipeline resources in AWS

set +e   # don't stop on errors (some resources may not exist)

echo "=========================================="
echo "Weather Pipeline - Nuclear Cleanup"
echo "=========================================="

echo ""
echo "→ Deleting Step Functions state machines..."
for SM in $(aws stepfunctions list-state-machines --query 'stateMachines[?contains(name,`weather`)].stateMachineArn' --output text); do
  aws stepfunctions delete-state-machine --state-machine-arn "$SM"
  echo "  ✓ Deleted $SM"
done

echo ""
echo "→ Deleting Lambda functions..."
for FN in $(aws lambda list-functions --query 'Functions[?contains(FunctionName,`weather`) || contains(FunctionName,`fetch`)].FunctionName' --output text); do
  aws lambda delete-function --function-name "$FN"
  echo "  ✓ Deleted $FN"
done

echo ""
echo "→ Deleting Lambda layer versions..."
for VERSION in $(aws lambda list-layer-versions --layer-name requests-layer --query 'LayerVersions[].Version' --output text 2>/dev/null); do
  aws lambda delete-layer-version --layer-name requests-layer --version-number "$VERSION"
  echo "  ✓ Deleted requests-layer version $VERSION"
done

echo ""
echo "→ Deleting Glue jobs..."
for JOB in $(aws glue get-jobs --query 'Jobs[?contains(Name,`weather`)].Name' --output text); do
  aws glue delete-job --job-name "$JOB"
  echo "  ✓ Deleted Glue job $JOB"
done

echo ""
echo "→ Deleting Glue crawlers..."
for CRAWLER in $(aws glue list-crawlers --query 'CrawlerNames[?contains(@,`weather`)]' --output text); do
  aws glue delete-crawler --name "$CRAWLER"
  echo "  ✓ Deleted crawler $CRAWLER"
done

echo ""
echo "→ Deleting Glue database..."
aws glue delete-database --name weather_analytics 2>/dev/null && echo "  ✓ Deleted weather_analytics"

echo ""
echo "→ Deleting EventBridge schedules..."
for SCHED in $(aws scheduler list-schedules --query 'Schedules[?contains(Name,`weather`)].Name' --output text 2>/dev/null); do
  aws scheduler delete-schedule --name "$SCHED"
  echo "  ✓ Deleted schedule $SCHED"
done

echo ""
echo "→ Deleting CloudWatch alarms..."
aws cloudwatch delete-alarms --alarm-names weather-lambda-errors 2>/dev/null && echo "  ✓ Deleted weather-lambda-errors"

echo ""
echo "→ Deleting SNS topics..."
for TOPIC in $(aws sns list-topics --query 'Topics[?contains(TopicArn,`weather`)].TopicArn' --output text); do
  aws sns delete-topic --topic-arn "$TOPIC"
  echo "  ✓ Deleted $TOPIC"
done

echo ""
echo "→ Deleting IAM roles..."
for ROLE in weather-lambda-role weather-glue-role weather-stepfunctions-role weather-scheduler-role; do
  # Detach all managed policies
  for POLICY in $(aws iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY"
  done
  # Delete all inline policies
  for INLINE in $(aws iam list-role-policies --role-name "$ROLE" --query 'PolicyNames' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "$ROLE" --policy-name "$INLINE"
  done
  # Delete the role
  aws iam delete-role --role-name "$ROLE" 2>/dev/null && echo "  ✓ Deleted $ROLE"
done

echo ""
echo "→ Emptying and deleting S3 bucket..."
BUCKET="weather-datalake-anass"
# Delete all current objects
aws s3 rm "s3://$BUCKET" --recursive 2>/dev/null
# Delete all object versions (bucket may be versioned)
aws s3api delete-objects --bucket "$BUCKET" \
  --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" 2>/dev/null
# Delete all delete markers
aws s3api delete-objects --bucket "$BUCKET" \
  --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" 2>/dev/null
# Delete the bucket itself
aws s3 rb "s3://$BUCKET" 2>/dev/null && echo "  ✓ Deleted bucket $BUCKET"

echo ""
echo "→ Force-deleting Secrets Manager entry..."
aws secretsmanager delete-secret \
    --secret-id openweathermap/api_key \
    --force-delete-without-recovery 2>/dev/null && echo "  ✓ Deleted openweathermap/api_key"

echo ""
echo "=========================================="
echo "VERIFICATION — should all be empty:"
echo "=========================================="
echo ""
echo "S3 buckets with 'weather':"
aws s3 ls | grep weather

echo ""
echo "IAM roles with 'weather':"
aws iam list-roles --query 'Roles[?contains(RoleName,`weather`)].RoleName' --output text

echo ""
echo "Glue databases with 'weather':"
aws glue get-databases --query 'DatabaseList[?contains(Name,`weather`)].Name' --output text

echo ""
echo "Lambda functions with 'weather'/'fetch':"
aws lambda list-functions --query 'Functions[?contains(FunctionName,`weather`) || contains(FunctionName,`fetch`)].FunctionName' --output text

echo ""
echo "SNS topics with 'weather':"
aws sns list-topics --query 'Topics[?contains(TopicArn,`weather`)].TopicArn' --output text

echo ""
echo "Cleanup complete."