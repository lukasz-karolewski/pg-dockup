FROM alpine:3

LABEL maintainer="Lukasz Karolewski"

ENV DIR="/home/backup"
RUN mkdir -p $DIR 
WORKDIR $DIR

ENV LOGFILE="/var/log/backup.log"
ENV LOCAL_BACKUP_DIR="$DIR/local-backup"
ENV BACKUP_NAME_PREFIX="pg_dump"
ENV PG_DUMP_OPTIONS="--clean --create --verbose"
ENV AWS_S3_CP_OPTIONS="--sse AES256"
ENV BACKUP_CRON_EXPRESSION="0 */2 * * *"

RUN mkdir -p $LOCAL_BACKUP_DIR
VOLUME $LOCAL_BACKUP_DIR

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    gnupg \
    gzip \
    postgresql-client \
    tzdata \
    unzip \
    aws-cli \
    dcron \
    findutils

# Setup cron
RUN mkdir -p /var/log /etc/cron.d && \
    touch $LOGFILE && \
    mkdir -p /etc/periodic

# Add health check
HEALTHCHECK --interval=5m --timeout=3s \
  CMD test -f $LOGFILE && grep -q "Backup process completed successfully" $LOGFILE && echo "OK" || exit 1

COPY . $DIR

CMD ["./run.sh"]