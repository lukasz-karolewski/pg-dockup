#!/usr/bin/env bash
set -e
set -x

# Find last backup file
LAST_BACKUP=$(aws s3 ls "s3://$AWS_S3_BUCKET_NAME" | awk -F " " '{print $4}' | grep ^"${BACKUP_NAME_PREFIX}" | sort -r | head -n 1)

# Download backup from S3
aws s3 cp "s3://$AWS_S3_BUCKET_NAME/$LAST_BACKUP" "$LOCAL_BACKUP_DIR/$LAST_BACKUP"