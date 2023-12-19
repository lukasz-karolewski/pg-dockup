FROM ubuntu:22.04
LABEL maintainer="Lukasz Karolewski"

ENV DIR="/home/backup"
RUN mkdir -p $DIR 
WORKDIR $DIR

ENV DEBIAN_FRONTEND=noninteractive
ENV LOGFILE="/var/log/backup.log"
ENV LOCAL_BACKUP_DIR="$DIR/local-backup"
ENV BACKUP_NAME_PREFIX="pg_dump"
ENV PG_DUMP_OPTIONS="--clean --create --verbose"
ENV AWS_S3_CP_OPTIONS="--sse AES256"
ENV BACKUP_CRON_EXPRESSION="0 */2 * * *"

RUN mkdir -p $LOCAL_BACKUP_DIR
VOLUME $LOCAL_BACKUP_DIR

RUN apt-get update && apt-get upgrade -y && apt-get install -y gnupg2 cron unzip lsb-release curl

# awscli 2.0
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" && unzip -q awscliv2.zip && ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli && rm -f awscliv2.zip && rm -rf aws

RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" >> /etc/apt/sources.list.d/pgdg.list
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update && apt-get install -y postgresql-client-16

COPY . $DIR

CMD ["./run.sh"]
