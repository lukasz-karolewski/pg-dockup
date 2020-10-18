#!/usr/bin/env bash
set -e
set -x

cat "$1" | gunzip | psql "${PG_CONNECTION_STRING}"