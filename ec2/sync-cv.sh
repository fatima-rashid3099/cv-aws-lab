#!/bin/bash
BUCKET="cv-23l-3099"
PREFIX="site/"
REGION="ap-southeast-2"
WEBROOT="/var/www/html"
LOG="/var/log/cv-sync.log"

# Read instance ID from the metadata service (IMDSv2 needs a token first)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

if aws s3 sync "s3://$BUCKET/$PREFIX" "$WEBROOT/" --delete --region "$REGION" --only-show-errors; then
  sed -i "s/{{HOSTED_ON}}/EC2 $INSTANCE_ID/g" "$WEBROOT/index.html"
  echo "$(date -u +%FT%TZ) sync OK instance=$INSTANCE_ID" >> "$LOG"
else
  echo "$(date -u +%FT%TZ) sync FAILED" >> "$LOG"
fi
