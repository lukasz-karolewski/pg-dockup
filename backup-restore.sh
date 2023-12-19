#!/usr/bin/env bash
function print_usage() 
{
  echo "Usage: ${0} backup.gz"
}

if [ "$#" -ne 1 ]; then
  print_usage
  exit 1
fi

set -e
set -x

PG_CONNECTION_STRING=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}/postgres
gunzip < "$1" | psql "${PG_CONNECTION_STRING}"
