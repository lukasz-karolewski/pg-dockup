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

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 "$SCRIPT_DIR/backup_s3.py" download

echo "Download process completed successfully at $(date)"
exit $SUCCESS
