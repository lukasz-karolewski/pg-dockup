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

# Generate filenames
readonly BACKUP_FILENAME="${BACKUP_NAME_PREFIX}-$(date +"%Y-%m-%dT%H-%M-%SZ").gz"
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

# Check if the backup contains PostgreSQL data by looking for PostgreSQL header signatures
if ! gunzip -c "$LOCAL_BACKUP_PATH" | head -c 50 | grep -q "PGDMP\|PostgreSQL\|pg_dump"; then
  echo "Backup doesn't appear to contain valid PostgreSQL backup data, aborting"
  exit $ERROR_INVALID_BACKUP_CONTENT
fi

# Print backup info
BACKUP_SIZE=$(du -h "${LOCAL_BACKUP_PATH}" | cut -f1)
echo "Backup created successfully: ${LOCAL_BACKUP_PATH} (${BACKUP_SIZE})"

# Keep only the most recent backups (count-based rotation)
echo "Cleaning up old backups (keeping ${BACKUP_RETENTION_COUNT} most recent)..."
ls -t "${LOCAL_BACKUP_DIR}/${BACKUP_NAME_PREFIX}"*.gz 2>/dev/null | tail -n +$((BACKUP_RETENTION_COUNT + 1)) | xargs -r rm -f

# --- S3 Upload Logic ---
S3_UPLOAD_REQUIRED=true # Default to true, set to false if checksums match

# Only check for duplicates and attempt upload if AWS is configured
if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
  echo "AWS credentials not configured, skipping S3 upload check and upload."
  S3_UPLOAD_REQUIRED=false
  # Keep the original exit code logic for this specific case later
else
  # Find latest *local* backup, excluding the one just created
  echo "Checking for latest local backup to compare..."
  # Find files, exclude the current one, print timestamp and path, sort by time, get the last one, extract path
  LATEST_LOCAL_BACKUP_PATH=$(find "${LOCAL_BACKUP_DIR}" -maxdepth 1 -type f -name "${BACKUP_NAME_PREFIX}*.gz" -not -path "${LOCAL_BACKUP_PATH}" -printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-)

  if [ -n "$LATEST_LOCAL_BACKUP_PATH" ]; then
      echo "Latest previous local backup found: ${LATEST_LOCAL_BACKUP_PATH}"
      echo "Calculating checksums..."
      LOCAL_CHECKSUM=$(md5sum "${LOCAL_BACKUP_PATH}" | awk '{ print $1 }')
      PREVIOUS_CHECKSUM=$(md5sum "${LATEST_LOCAL_BACKUP_PATH}" | awk '{ print $1 }')
      echo "New backup checksum: ${LOCAL_CHECKSUM}"
      echo "Previous backup checksum: ${PREVIOUS_CHECKSUM}"

      if [ "$LOCAL_CHECKSUM" == "$PREVIOUS_CHECKSUM" ]; then
          echo "Backup content is identical to the latest local backup (${LATEST_LOCAL_BACKUP_PATH}). Skipping S3 upload."
          S3_UPLOAD_REQUIRED=false
          echo "Removing redundant local backup: ${LOCAL_BACKUP_PATH}"
          rm -f "${LOCAL_BACKUP_PATH}"
      else
          echo "Backup content differs from the latest local backup. Proceeding with S3 upload."
          # S3_UPLOAD_REQUIRED remains true
      fi
  else
      echo "No previous local backups found for comparison. Proceeding with S3 upload."
      # S3_UPLOAD_REQUIRED remains true
  fi
fi # end AWS credential check

# Upload the backup to S3 only if required
if [ "$S3_UPLOAD_REQUIRED" = true ]; then
  # Double check AWS config before attempting upload (redundant check based on above logic, but safe)
  if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
     echo "AWS credentials not configured. Cannot upload."
     # Exit with the specific error code for missing AWS config
     echo "Backup completed locally at $(date)"
     exit $ERROR_AWS_NOT_CONFIGURED
  fi
  echo "Uploading backup to S3..."
  if aws s3 --region "${AWS_S3_REGION}" cp "${LOCAL_BACKUP_PATH}" "s3://${AWS_S3_BUCKET_NAME}/${BACKUP_FILENAME}" ${AWS_S3_CP_OPTIONS}; then
    echo "Backup successfully uploaded to s3://${AWS_S3_BUCKET_NAME}/${BACKUP_FILENAME}"
  else
    echo "ERROR: Failed to upload backup to S3"
    exit $ERROR_AWS_UPLOAD_FAILED
  fi
else
    # If upload was skipped (either due to identical content or missing AWS config initially)
    if [ -n "${AWS_ACCESS_KEY_ID}" ]; then # Only print skipped message if AWS *was* configured
        echo "S3 Upload skipped as content matched previous local backup."
    else
        # This case is handled by the initial AWS config check which exits
         echo "S3 Upload skipped due to missing AWS configuration." # Should not be reached if exit happens above
    fi
fi
# --- S3 Logic End ---

# Handle the case where AWS wasn't configured from the start
if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "${AWS_SECRET_ACCESS_KEY}" ] || [ -z "${AWS_S3_REGION}" ] || [ -z "${AWS_S3_BUCKET_NAME}" ]; then
  # Check again to ensure the correct exit code is used if S3 upload was skipped *because* of missing config
  if [ "$S3_UPLOAD_REQUIRED" = false ]; then # Check if it was set to false by the initial check
     echo "Backup completed locally at $(date)"
     exit $ERROR_AWS_NOT_CONFIGURED
  fi
fi

echo "Backup process completed successfully at $(date)"
exit $SUCCESS