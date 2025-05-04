FROM alpine:3

LABEL maintainer="Lukasz Karolewski" 

ENV DIR="/home/backup"
ENV LOGFILE="/var/log/backup.log"
ENV LOCAL_BACKUP_DIR="$DIR/local-backup"
ENV BACKUP_NAME_PREFIX="pg_dump"
ENV PG_DUMP_OPTIONS="--clean --create --verbose"
ENV AWS_S3_CP_OPTIONS="--sse AES256"
ENV BACKUP_CRON_EXPRESSION="0 */2 * * *" 
ENV CROND_LOG_LEVEL="4"

# Create necessary directories and log file early
# Also create the standard crontabs directory
RUN mkdir -p "$DIR" "$LOCAL_BACKUP_DIR" $(dirname "$LOGFILE") /etc/crontabs && \
    touch "$LOGFILE"

# Set the working directory
WORKDIR "$DIR"

# Declare the directory where local backups will be stored as a volume
# This allows mounting this directory to persist backups outside the container
VOLUME "$LOCAL_BACKUP_DIR"

# Install dependencies, including dcron and a minimal init system (tini)
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
    findutils \
    tini # Added tini for better signal handling

# Copy scripts and application files into the working directory ($DIR)
COPY . "$DIR"

# Set tini as the entrypoint to handle signals gracefully
ENTRYPOINT ["/sbin/tini", "--"]

CMD ["./run.sh"]