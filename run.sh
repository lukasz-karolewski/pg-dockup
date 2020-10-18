#!/usr/bin/env bash
set -e
set -x

# run backup immiedieately
./backup-create.sh >> "${LOGFILE}" 2>&1

# set environment vars for cron
env > /etc/environment

# configure crontab
CRON_FILE=/etc/cron.d/backup
CRON_LINE="$BACKUP_CRON_EXPRESSION root $DIR/backup-create.sh >> ${LOGFILE} 2>&1"

echo "$CRON_LINE" > $CRON_FILE
printf "\n" >> $CRON_FILE # needs a newline

chmod 0644 $CRON_FILE

# https://stackoverflow.com/questions/21926465/issues-running-cron-in-docker-on-different-hosts
sed -e '/pam_loginuid.so/ s/^#*/#/' -i /etc/pam.d/cron

service cron start && tail -f "${LOGFILE}"
