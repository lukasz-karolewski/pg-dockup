#!/usr/bin/env bash
set -e
set -x

# Create log file if it doesn't exist
mkdir -p "$(dirname "${LOGFILE}")"
touch "${LOGFILE}"

# Run backup immediately
./backup-create.sh >> "${LOGFILE}" 2>&1

# Set environment vars for cron
env > /etc/environment

# Configure crontab for Alpine's crond
# Always use crontabs file to ensure exact cron expression is respected
CRON_FILE=/etc/crontabs/root
CRON_LINE="$BACKUP_CRON_EXPRESSION $DIR/backup-create.sh >> ${LOGFILE} 2>&1"

# Ensure we're adding to the file, not overwriting it
echo "$CRON_LINE" >> $CRON_FILE

# Add a debug line to verify cron is working
echo "*/5 * * * * echo 'Cron is working' >> ${LOGFILE}" >> $CRON_FILE

# Make sure crontab is properly configured
chmod 0600 $CRON_FILE

# Start cron based on the system
if command -v crond > /dev/null 2>&1; then
  # Alpine uses crond
  crond -f -d 8 &
else
  echo "No cron service found"
  exit 1
fi

# Follow log file
tail -f "${LOGFILE}"