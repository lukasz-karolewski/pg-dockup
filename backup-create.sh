#!/usr/bin/env bash
set -e
# set -x

# Error codes
readonly SUCCESS=0
readonly ERROR_PG_DUMP_FAILED=1
readonly ERROR_BACKUP_TOO_SMALL=2
readonly ERROR_INVALID_BACKUP_CONTENT=3
readonly ERROR_AWS_NOT_CONFIGURED=4
readonly ERROR_AWS_UPLOAD_FAILED=5

# Add script description and usage
# Purpose: Creates PostgreSQL database backups and uploads to S3
echo "Starting backup at $(date)"
export PATH=$PATH:/usr/bin:/usr/local/bin:/bin

# Validate required environment variables
if [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ] || [ -z "${POSTGRES_HOST}" ] || [ -z "${POSTGRES_DB}" ]; then
  echo "ERROR: Required PostgreSQL environment variables not set"
  echo "Required: POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_HOST, POSTGRES_DB"
  exit $ERROR_PG_DUMP_FAILED
fi

if [ -z "${LOCAL_BACKUP_DIR}" ] || [ -z "${BACKUP_NAME_PREFIX}" ]; then
  echo "ERROR: Backup configuration variables not set"
  echo "Required: LOCAL_BACKUP_DIR, BACKUP_NAME_PREFIX"
  exit $ERROR_PG_DUMP_FAILED
fi

# Create backup directory if it doesn't exist
mkdir -p "${LOCAL_BACKUP_DIR}"

# Generate filenames
readonly BACKUP_FILENAME="${BACKUP_NAME_PREFIX}-$(date +"%Y-%m-%dT%H-%M-%SZ").gz"
readonly LOCAL_BACKUP_PATH="${LOCAL_BACKUP_DIR}/${BACKUP_FILENAME}"

# Run backup with proper error checking
PG_CONNECTION_STRING=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}/${POSTGRES_DB}
echo "Running pg_dump..."
if ! pg_dump "${PG_CONNECTION_STRING}" ${PG_DUMP_OPTIONS} | gzip > "$LOCAL_BACKUP_PATH"; then
  echo "pg_dump failed, aborting"
  rm -f "$LOCAL_BACKUP_PATH"
  exit $ERROR_PG_DUMP_FAILED
fi

# Validate backup file contains actual PostgreSQL data
echo "Validating backup..."
if [ "$(stat -c%s "$LOCAL_BACKUP_PATH")" -lt 1024 ]; then
  echo "Backup file is suspiciously small (less than 1kb), aborting"
  exit $ERROR_BACKUP_TOO_SMALL
fi

# Check if the backup contains PostgreSQL data by looking for PostgreSQL header signatures
if ! gunzip -c "$LOCAL_BACKUP_PATH" | head -c 50 | grep -q "PGDMP\|PostgreSQL\|pg_dump"; then
  echo "Backup doesn't appear to contain valid PostgreSQL backup data, aborting"
  exit $ERROR_INVALID_BACKUP_CONTENT
fi

# Print backup info
BACKUP_SIZE=$(du -h "${LOCAL_BACKUP_PATH}" | cut -f1)
echo "Backup created successfully: ${LOCAL_BACKUP_PATH} (${BACKUP_SIZE})"

# Remove local backups older than 30 days 
echo "Cleaning up old backups..."
find "${LOCAL_BACKUP_DIR}" -type f -name "${BACKUP_NAME_PREFIX}*.gz" -mtime +30 -delete

if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
  echo "AWS credentials not configured, skipping S3 upload"
  echo "Backup completed locally at $(date)"
  exit $ERROR_AWS_NOT_CONFIGURED
fi 

# Upload the backup to S3
echo "Uploading backup to S3..."
if aws s3 --region "${AWS_S3_REGION}" cp "${LOCAL_BACKUP_PATH}" "s3://${AWS_S3_BUCKET_NAME}/${BACKUP_FILENAME}" ${AWS_S3_CP_OPTIONS}; then
  echo "Backup successfully uploaded to s3://${AWS_S3_BUCKET_NAME}/${BACKUP_FILENAME}"
else
  echo "ERROR: Failed to upload backup to S3"
  exit $ERROR_AWS_UPLOAD_FAILED
fi

echo "Backup process completed successfully at $(date)"
exit $SUCCESS