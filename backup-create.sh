#!/usr/bin/env bash
set -e
set -o pipefail
# set -x

# Error codes
readonly SUCCESS=0
readonly ERROR_PG_DUMP_FAILED=1
readonly ERROR_BACKUP_TOO_SMALL=2
readonly ERROR_INVALID_BACKUP_CONTENT=3
readonly ERROR_AWS_NOT_CONFIGURED=4
readonly ERROR_AWS_UPLOAD_FAILED=5
readonly ERROR_BACKUP_ALREADY_RUNNING=6

# Add script description and usage
# Purpose: Creates PostgreSQL database backups and uploads to S3
echo "Starting backup at $(date)"
export PATH=$PATH:/usr/bin:/usr/local/bin:/bin

# Collect any additional pg_dump arguments passed to the script
# shellcheck disable=SC2124
ADDITIONAL_ARGS="$@"

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

# Set default retention count if not specified
BACKUP_RETENTION_COUNT=${BACKUP_RETENTION_COUNT:-10}

# Create backup directory if it doesn't exist
mkdir -p "${LOCAL_BACKUP_DIR}"

readonly LOCK_DIR="${LOCAL_BACKUP_DIR}/.backup.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another backup is already running, skipping this run"
  exit $ERROR_BACKUP_ALREADY_RUNNING
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# Generate filenames
readonly BACKUP_FILENAME="${BACKUP_NAME_PREFIX}-$(date -u +"%Y-%m-%dT%H-%M-%SZ").gz"
readonly LOCAL_BACKUP_PATH="${LOCAL_BACKUP_DIR}/${BACKUP_FILENAME}"

# Run backup with proper error checking
# Use PGPASSWORD to avoid exposing password in process list
export PGPASSWORD="${POSTGRES_PASSWORD}"

# Combine default options with any additional arguments
ALL_OPTIONS="${PG_DUMP_OPTIONS} ${ADDITIONAL_ARGS}"
echo "Running pg_dump with options: ${ALL_OPTIONS}..."
# shellcheck disable=SC2086 
if ! pg_dump -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" ${ALL_OPTIONS} | gzip > "$LOCAL_BACKUP_PATH"; then
  echo "pg_dump failed, aborting"
  rm -f "$LOCAL_BACKUP_PATH"
  exit $ERROR_PG_DUMP_FAILED
fi

# Clear the password from environment
unset PGPASSWORD

# Validate backup file contains actual PostgreSQL data
echo "Validating backup..."
if [ "$(stat -c%s "$LOCAL_BACKUP_PATH")" -lt 1024 ]; then
  echo "Backup file is suspiciously small (less than 1kb), aborting"
  exit $ERROR_BACKUP_TOO_SMALL
fi

if ! gzip -t "$LOCAL_BACKUP_PATH"; then
  echo "Backup gzip integrity check failed, aborting"
  exit $ERROR_INVALID_BACKUP_CONTENT
fi

# Check if the backup contains PostgreSQL data by looking for PostgreSQL header signatures
BACKUP_HEADER=$(set +o pipefail; gunzip -c "$LOCAL_BACKUP_PATH" | head -c 50)
if ! printf '%s' "$BACKUP_HEADER" | grep -q "PGDMP\|PostgreSQL\|pg_dump"; then
  echo "Backup doesn't appear to contain valid PostgreSQL backup data, aborting"
  exit $ERROR_INVALID_BACKUP_CONTENT
fi

# Print backup info
BACKUP_SIZE=$(du -h "${LOCAL_BACKUP_PATH}" | cut -f1)
echo "Backup created successfully: ${LOCAL_BACKUP_PATH} (${BACKUP_SIZE})"

# A local dump alone is not a successful remote backup. Preserve every local
# recovery copy if upload or pointer publication fails.
if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
  echo "AWS credentials not configured; retaining all local backups"
  exit $ERROR_AWS_NOT_CONFIGURED
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if ! python3 "$SCRIPT_DIR/backup_s3.py" upload "$LOCAL_BACKUP_PATH"; then
  echo "ERROR: S3 publication failed; retaining all local backups"
  exit $ERROR_AWS_UPLOAD_FAILED
fi
python3 "$SCRIPT_DIR/backup_s3.py" rotate

echo "Backup process completed successfully at $(date)"
exit $SUCCESS
