# pg-dockup

[![Docker Image Version](https://img.shields.io/docker/v/lkarolewski/pg-dockup?sort=semver)](https://hub.docker.com/r/lkarolewski/pg-dockup)

A containerized PostgreSQL backup solution that automatically creates database backups and uploads them to Amazon S3.

## Features

- Scheduled PostgreSQL database backups using `pg_dump`
- Amazon S3 integration for secure, off-site storage
- Configurable backup schedule with cron expressions
- Local backup storage with retention policy
- Simple backup restoration process
- Health checks to monitor backup status

## Quick Start

### Prerequisites

- Docker or Docker Compose
- PostgreSQL database credentials
- AWS S3 bucket and credentials

### Docker Compose Setup

```yaml
version: "3"
services:
  postgres:
    image: "postgres:latest"
    # Add your PostgreSQL configuration here
    
  db-backup:
    restart: unless-stopped
    image: lkarolewski/pg-dockup:latest
    depends_on:
      - postgres
    environment:
      # PostgreSQL Connection
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=your_database
      - POSTGRES_USER=your_username
      - POSTGRES_PASSWORD=your_password
      
      # AWS S3 Configuration
      - AWS_ACCESS_KEY_ID=your_aws_key
      - AWS_SECRET_ACCESS_KEY=your_aws_secret
      - AWS_S3_BUCKET_NAME=your_bucket_name
      - AWS_S3_REGION=your_aws_region
      
      # Backup Schedule
      - BACKUP_CRON_EXPRESSION="0 2 * * *"  # Daily at 2 AM
      
      # System Configuration (optional)
      - CROND_LOG_LEVEL=4  # configure log level for cron daemon
```

## Usage

### Creating a One-Time Backup

Run a one-time backup instead of waiting for the scheduled cron job:

```bash
docker run --rm --env-file .env lkarolewski/pg-dockup:latest ./backup-create.sh
```

You can also pass additional pg_dump arguments directly to the script:

```bash
docker run --rm --env-file .env lkarolewski/pg-dockup:latest ./backup-create.sh --schema=public --no-owner
```

### Downloading the Latest Backup

Download the most recent backup from S3 to your current directory:

```bash
docker run --rm --env-file .env -v "$(pwd)":/home/backup/local-backup \
  lkarolewski/pg-dockup:latest ./backup-download-last.sh
```

### Restoring a Backup

Restore from a backup file:

```bash
docker run --rm --env-file .env -v "$(pwd)":/home/backup/local-backup \
  lkarolewski/pg-dockup:latest ./backup-restore.sh your_backup_file.gz
```

## Configuration

### Required Environment Variables

#### PostgreSQL Connection Variables

| Variable | Description |
|----------|-------------|
| `POSTGRES_HOST` | PostgreSQL server hostname or IP address |
| `POSTGRES_DB` | Database name to back up |
| `POSTGRES_USER` | PostgreSQL username |
| `POSTGRES_PASSWORD` | PostgreSQL password |

#### AWS S3 Variables

| Variable | Description |
|----------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key with S3 permissions |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key |
| `AWS_S3_BUCKET_NAME` | S3 bucket name for storing backups |
| `AWS_S3_REGION` | AWS region for the S3 bucket |

### Optional Variables

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `BACKUP_CRON_EXPRESSION` | `0 */2 * * *` | Cron schedule expression (default: every 2 hours) |
| `BACKUP_NAME_PREFIX` | `pg_dump` | Prefix for backup filenames |
| `PG_DUMP_OPTIONS` | `--clean --create --verbose` | Options passed to pg_dump command |
| `AWS_S3_CP_OPTIONS` | `--sse AES256` | Options for S3 upload command |
| `CROND_LOG_LEVEL` | `5` | Log level for crond (0-9, where 0 is least verbose and 9 is most verbose) |

## How It Works

1. The container runs a cron job based on the configured schedule
2. When triggered, it creates a compressed PostgreSQL dump
3. The backup is validated for integrity and minimum size
4. The backup is uploaded to the specified S3 bucket
5. Local backups older than 30 days are automatically cleaned up

## Error Handling

The backup process includes several validation steps with specific error codes:
- Verification of PostgreSQL connection parameters
- Validation of backup file size and content
- Error handling for S3 upload failures

## Building Locally

```bash
git clone https://github.com/yourusername/pg-dockup.git
cd pg-dockup
docker build -t pg-dockup .
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
