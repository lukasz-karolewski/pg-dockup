#!/usr/bin/env bash
set -e
# set -x

echo "Starting backup"
export PATH=$PATH:/usr/bin:/usr/local/bin:/bin

# Generate filenames
readonly BACKUP_FILENAME="${BACKUP_NAME_PREFIX}-$(date +"%Y-%m-%dT%H-%M-%SZ").gz"
readonly LOCAL_BACKUP_PATH="${LOCAL_BACKUP_DIR}/${BACKUP_FILENAME}"

# Run backup
PG_CONNECTION_STRING=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}/${POSTGRES_DB}
pg_dump "${PG_CONNECTION_STRING}" ${PG_DUMP_OPTIONS} | gzip > "$LOCAL_BACKUP_PATH"

# Remove local backups older than 30 days 
find . -type f -name "${BACKUP_NAME_PREFIX}*.gz" -mtime +30 -delete

if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
  echo awscli not configured, exiting
  exit 0
fi 

# Upload the backup to S3
aws s3 --region "${AWS_S3_REGION}" cp "${LOCAL_BACKUP_PATH}" "s3://${AWS_S3_BUCKET_NAME}/${BACKUP_FILENAME}.gz" "${AWS_S3_CP_OPTIONS}"
echo "backup done"