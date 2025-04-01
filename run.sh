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

# Configure crontab
CRON_FILE=/etc/cron.d/backup
CRON_LINE="$BACKUP_CRON_EXPRESSION root $DIR/backup-create.sh >> ${LOGFILE} 2>&1"

echo "$CRON_LINE" > $CRON_FILE
printf "\n" >> $CRON_FILE # needs a newline

chmod 0644 $CRON_FILE

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