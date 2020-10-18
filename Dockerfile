FROM ubuntu:20.04
LABEL maintainer="Lukasz Karolewski"

ENV BACKUP_NAME_PREFIX pg_dump
ENV AWS_S3_CP_OPTIONS --sse AES256
ENV PG_DUMP_OPTIONS --verbose
ENV DIR /home/backup
ENV LOCAL_BACKUP_DIR $DIR/local-backup
ENV BACKUP_CRON_EXPRESSION="0 */2 * * *"
ENV LOGFILE=/var/log/backup.log

RUN mkdir -p $DIR 
WORKDIR $DIR

VOLUME $LOCAL_BACKUP_DIR

RUN apt-get update && apt-get upgrade -y
RUN apt-get install wget gnupg2 cron unzip -y

RUN wget "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -O "awscliv2.zip" && unzip awscliv2.zip && ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli && rm -f awscliv2.zip && rm -rf aws

RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main' >> /etc/apt/sources.list.d/pgdg.list
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN apt-get update && apt-get install -y postgresql-client-13

COPY . $DIR

CMD ["./run.sh"]
