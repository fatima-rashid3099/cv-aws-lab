#!/bin/bash
# Usage: ./collect-evidence.sh <bucket-name> <ec2-address> <lambda-address>

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
  exit 1
fi

BUCKET="$1"
EC2_URL="${2%/}"
LAMBDA_URL="${3%/}"
OUT="evidence.txt"

REGION="ap-southeast-2"
export AWS_DEFAULT_REGION="$REGION"
EC2_NAME="cv-ec2-23l-3099"
EC2_ROLE="cv-ec2-role-23l-3099"
EC2_POLICY="cv-ec2-s3-read"
LAMBDA_FN="cv-func-23l-3099"
LAMBDA_ROLE="cv-lambda-role-23l-3099"
LAMBDA_POLICY="cv-lambda-s3-read"

: > "$OUT"

section() { echo "" >> "$OUT"; echo "== $1 ==" >> "$OUT"; }
run() { "$@" >> "$OUT" 2>&1 || echo "(command failed: $1 $2 $3)" >> "$OUT"; }
check() {
  local result
  result=$(curl -s -o /dev/null -m 15 -w "status=%{http_code} content_type=%{content_type}" "$2") || result="(curl failed)"
  echo "$1 $2 -> $result" >> "$OUT"
}

section caller
run aws sts get-caller-identity

section public-access
run aws s3api get-public-access-block --bucket "$BUCKET"

section versioning
run aws s3api get-bucket-versioning --bucket "$BUCKET"

section objects
run aws s3 ls "s3://$BUCKET/site/" --recursive

section ec2-policy
run aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$EC2_POLICY"

section lambda-policy
run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE"
run aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$LAMBDA_POLICY"

section security-group
SG_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$EC2_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].SecurityGroups[0].GroupId' --output text 2>/dev/null)
run aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[].IpPermissions' --output json

section instance
run aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$EC2_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,IMDS:MetadataOptions.HttpTokens,Profile:IamInstanceProfile.Arn}' \
  --output json

section endpoints
check "EC2    /          " "$EC2_URL/"
check "EC2    /style.css " "$EC2_URL/style.css"
check "EC2    /cv.pdf    " "$EC2_URL/cv.pdf"
check "Lambda /          " "$LAMBDA_URL/"
check "Lambda /style.css " "$LAMBDA_URL/style.css"
check "Lambda /cv.pdf    " "$LAMBDA_URL/cv.pdf"
check "Lambda /anything  " "$LAMBDA_URL/anything"
check "S3 direct         " "https://$BUCKET.s3.$REGION.amazonaws.com/site/index.html"

section lambda-logs
LOGS=$(aws logs tail "/aws/lambda/$LAMBDA_FN" --since 1d 2>&1) \
  && echo "$LOGS" | tail -n 10 >> "$OUT" \
  || echo "(command failed) $LOGS" >> "$OUT"

section log-retention
run aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/$LAMBDA_FN" \
  --query 'logGroups[].[logGroupName,retentionInDays]' --output text

echo "DONE"
