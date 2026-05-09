#!/usr/bin/env bash
set -e

# Create log file if it doesn't exist
mkdir -p "$(dirname "${LOGFILE}")"
touch "${LOGFILE}"

# Run backup immediately, but do not prevent scheduled backups from starting.
if ! ./backup-create.sh >> "${LOGFILE}" 2>&1; then
  echo "Initial backup failed at $(date); scheduled backups will still start." >> "${LOGFILE}"
fi

# Set environment vars for cron
env > /etc/environment

# Configure crontab for Alpine's crond
# Always use crontabs file to ensure exact cron expression is respected
CRON_FILE=/etc/crontabs/root
CRON_LINE="$BACKUP_CRON_EXPRESSION $DIR/backup-create.sh >> ${LOGFILE} 2>&1"

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
