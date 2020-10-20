
# pg-dockup - postgres dockerized backup

Dockerized cron job to pg_dump to s3.

## Usage with docker-compose

```
version: "3"
services:
  postgres:
    image: "postgres:latest"

  db-backup:
    restart: unless-stopped
    image: lkarolewski/pg-dockup:latest
    depends_on:
      - postgres
    environment:
      - POSTGRES_HOST=""
      - POSTGRES_DB=""
      - POSTGRES_USER=""
      - POSTGRES_PASSWORD=""
      - AWS_ACCESS_KEY_ID=""
      - AWS_SECRET_ACCESS_KEY=""
      - AWS_S3_BUCKET_NAME=""
      - AWS_S3_REGION=""
      - BACKUP_CRON_EXPRESSION="0 2 * * *"
```

## Usage

### One time backup

    docker run --rm --env-file .env lkarolewski/pg-dockup:latest ./backup-create.sh


### Download latest backup

    docker run --rm --env-file .env -v "$(pwd)":/home/backup/local-backup lkarolewski/pg-dockup:latest ./backup-download-last.sh


### Restore backup

    docker run --rm --env-file .env -v "$(pwd)":/home/backup/local-backup lkarolewski/pg-dockup:latest ./backup-restore.sh


## env variables

### required to create and restore backup

    POSTGRES_HOST=""
    POSTGRES_DB=""
    POSTGRES_USER=""
    POSTGRES_PASSWORD=""

### required to copy to and from s3   
    AWS_ACCESS_KEY_ID=""
    AWS_SECRET_ACCESS_KEY=""
    AWS_S3_BUCKET_NAME=""
    AWS_S3_REGION=""
        
### optional - have default values
    BACKUP_CRON_EXPRESSION="0 */2 * * *" #Every two hours
    BACKUP_NAME_PREFIX=pg_dump
    PG_DUMP_OPTIONS="--clean --create --verbose"
    AWS_S3_CP_OPTIONS=--sse AES256 # options appended to awscli cp command, refer to `http://docs.aws.amazon.com/cli/latest/reference/s3/cp.html`
