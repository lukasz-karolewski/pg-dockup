#!/usr/bin/env bash
set -e
# set -x

# Error codes
readonly SUCCESS=0
readonly ERROR_AWS_NOT_CONFIGURED=1
readonly ERROR_NO_BACKUPS_FOUND=2
readonly ERROR_DOWNLOAD_FAILED=3
readonly ERROR_MISSING_CONFIG=4

# Purpose: Downloads the most recent PostgreSQL backup from S3
echo "Starting download of latest backup at $(date)"
export PATH=$PATH:/usr/bin:/usr/local/bin:/bin

# Validate required environment variables
if [ -z "${LOCAL_BACKUP_DIR}" ] || [ -z "${BACKUP_NAME_PREFIX}" ]; then
  echo "ERROR: Backup configuration variables not set"
  echo "Required: LOCAL_BACKUP_DIR, BACKUP_NAME_PREFIX"
  exit $ERROR_MISSING_CONFIG
fi

# Create backup directory if it doesn't exist
mkdir -p "${LOCAL_BACKUP_DIR}"

# Check AWS configuration
if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
  echo "ERROR: AWS credentials not configured"
  echo "Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_S3_REGION, AWS_S3_BUCKET_NAME"
  exit $ERROR_AWS_NOT_CONFIGURED
fi 

# Find the last backup file
echo "Searching for latest backup in s3://${AWS_S3_BUCKET_NAME} with prefix ${BACKUP_NAME_PREFIX}..."
LAST_BACKUP=$(aws s3 ls "s3://$AWS_S3_BUCKET_NAME/" | awk -F " " '{print $4}' | grep ^"${BACKUP_NAME_PREFIX}" | sort -r | head -n 1)

if [ -z "$LAST_BACKUP" ]; then
  echo "ERROR: No backups found matching prefix ${BACKUP_NAME_PREFIX}"
  exit $ERROR_NO_BACKUPS_FOUND
fi

echo "Found latest backup: ${LAST_BACKUP}"

# Download backup from S3
echo "Downloading backup from S3..."
if aws s3 cp "s3://$AWS_S3_BUCKET_NAME/$LAST_BACKUP" "$LOCAL_BACKUP_DIR/$LAST_BACKUP"; then
  echo "Backup successfully downloaded to $LOCAL_BACKUP_DIR/$LAST_BACKUP"
  
  # Print backup info
  BACKUP_SIZE=$(du -h "${LOCAL_BACKUP_DIR}/${LAST_BACKUP}" | cut -f1)
  echo "Downloaded backup size: ${BACKUP_SIZE}"
else
  echo "ERROR: Failed to download backup from S3"
  exit $ERROR_DOWNLOAD_FAILED
fi

echo "Download process completed successfully at $(date)"
exit $SUCCESS
