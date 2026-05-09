#!/usr/bin/env bash
set -e

# Create log file if it doesn't exist
mkdir -p "$(dirname "${LOGFILE}")"
touch "${LOGFILE}"

# Run backup immediately, but do not prevent scheduled backups from starting.
if ! ./backup-create.sh >> "${LOGFILE}" 2>&1; then
  echo "Initial backup failed at $(date); scheduled backups will still start." >> "${LOGFILE}"
fi

# Write only the environment required by scheduled backups.
ENV_FILE=/etc/pg-dockup.env
umask 077
: > "$ENV_FILE"
for name in \
  AWS_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY \
  AWS_S3_BUCKET_NAME \
  AWS_S3_CP_OPTIONS \
  AWS_S3_REGION \
  BACKUP_NAME_PREFIX \
  BACKUP_RETENTION_COUNT \
  DIR \
  LOCAL_BACKUP_DIR \
  LOGFILE \
  PG_DUMP_OPTIONS \
  POSTGRES_DB \
  POSTGRES_HOST \
  POSTGRES_PASSWORD \
  POSTGRES_USER
do
  if [ -n "${!name+x}" ]; then
    printf 'export %s=%q\n' "$name" "${!name}" >> "$ENV_FILE"
  fi
done
chmod 0600 "$ENV_FILE"

CRON_RUNNER=/usr/local/bin/pg-dockup-cron
cat > "$CRON_RUNNER" <<'EOF'
#!/usr/bin/env bash
set -e
source /etc/pg-dockup.env
exec "$DIR/backup-create.sh" >> "$LOGFILE" 2>&1
EOF
chmod 0700 "$CRON_RUNNER"

# Configure crontab for Alpine's crond
# Always use crontabs file to ensure exact cron expression is respected
CRON_FILE=/etc/crontabs/root
CRON_LINE="$BACKUP_CRON_EXPRESSION $CRON_RUNNER"

# Write the managed crontab entry.
echo "$CRON_LINE" > $CRON_FILE

# Make sure crontab is properly configured
chmod 0600 $CRON_FILE

# Start cron based on the system
if command -v crond > /dev/null 2>&1; then
  # Alpine uses crond
  # Use configured log level from environment variable
  crond -f -l "${CROND_LOG_LEVEL}" &
else
  echo "No cron service found"
  exit 1
fi

# Follow log file
tail -f "${LOGFILE}"
