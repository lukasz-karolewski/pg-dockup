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

gunzip < "$1" | psql -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -d postgres
