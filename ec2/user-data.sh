#!/bin/bash
dnf install -y httpd
systemctl enable --now httpd

# --- the sync script ---
cat > /usr/local/bin/sync-cv.sh << 'EOF'
#!/bin/bash
BUCKET="cv-23l-3099"
PREFIX="site/"
REGION="ap-southeast-2"
WEBROOT="/var/www/html"
LOG="/var/log/cv-sync.log"

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

if aws s3 sync "s3://$BUCKET/$PREFIX" "$WEBROOT/" --delete --region "$REGION" --only-show-errors; then
  sed -i "s/{{HOSTED_ON}}/EC2 $INSTANCE_ID/g" "$WEBROOT/index.html"
  echo "$(date -u +%FT%TZ) sync OK instance=$INSTANCE_ID" >> "$LOG"
else
  echo "$(date -u +%FT%TZ) sync FAILED" >> "$LOG"
fi
EOF
chmod +x /usr/local/bin/sync-cv.sh

# --- systemd timer: runs the sync every 2 minutes ---
cat > /etc/systemd/system/cv-sync.service << 'EOF'
[Unit]
Description=Sync CV from S3

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat > /etc/systemd/system/cv-sync.timer << 'EOF'
[Unit]
Description=Run CV sync every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cv-sync.timer

# --- run the sync once now ---
/usr/local/bin/sync-cv.sh
