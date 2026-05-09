#!/usr/bin/env bash
set -e
set -o pipefail

function print_usage()
{
  echo "Usage: ${0} backup.gz"
}

if [ "$#" -ne 1 ]; then
  print_usage
  exit 1
fi

if [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ] || [ -z "${POSTGRES_HOST}" ]; then
  echo "ERROR: Required PostgreSQL environment variables not set"
  echo "Required: POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_HOST"
  exit 1
fi

export PGPASSWORD="${POSTGRES_PASSWORD}"
trap 'unset PGPASSWORD' EXIT

if ! gzip -t "$1"; then
  echo "ERROR: Backup gzip integrity check failed"
  exit 1
fi

POSTGRES_RESTORE_DB="${POSTGRES_RESTORE_DB:-postgres}"
BACKUP_HEADER=$(set +o pipefail; gunzip -c "$1" | head -c 5)

if [ "$BACKUP_HEADER" = "PGDMP" ]; then
  gunzip < "$1" | pg_restore -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${POSTGRES_RESTORE_DB}"
else
  gunzip < "$1" | psql -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d "${POSTGRES_RESTORE_DB}"
fi
