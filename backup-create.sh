#!/usr/bin/env bash
set -e
# set -x

# Error codes
readonly SUCCESS=0
readonly ERROR_PG_DUMP_FAILED=1
readonly ERROR_BACKUP_TOO_SMALL=2
readonly ERROR_INVALID_BACKUP_CONTENT=3
readonly ERROR_AWS_NOT_CONFIGURED=4

echo "Starting backup"
export PATH=$PATH:/usr/bin:/usr/local/bin:/bin

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

# Remove local backups older than 30 days 
find . -type f -name "${BACKUP_NAME_PREFIX}*.gz" -mtime +30 -delete

if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
  echo "awscli not configured, exiting"
  exit $ERROR_AWS_NOT_CONFIGURED
fi 

# Upload the backup to S3
echo "Uploading backup to S3..."
aws s3 --region "${AWS_S3_REGION}" cp "${LOCAL_BACKUP_PATH}" "s3://${AWS_S3_BUCKET_NAME}/${BACKUP_FILENAME}" ${AWS_S3_CP_OPTIONS}
echo "backup done"
exit $SUCCESS