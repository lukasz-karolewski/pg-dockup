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

cat "$1" | gunzip | psql "${PG_CONNECTION_STRING}"