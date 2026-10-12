#!/usr/bin/env bash
# Shared helpers sourced by the pg-dockup scripts.

# Credentials that can be given as NAME or as NAME_FILE (Docker secrets).
readonly PG_DOCKUP_FILE_ENV_VARS="POSTGRES_USER POSTGRES_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY"

# file_env NAME
# If NAME_FILE is set, export NAME with the contents of that file (trailing
# newlines stripped) and unset NAME_FILE. Setting both NAME and NAME_FILE is
# an error. Same convention as the official postgres image.
# Values are never printed.
file_env() {
  local var="$1"
  local file_var="${var}_FILE"
  local file="${!file_var:-}"

  if [ -n "${!var:-}" ] && [ -n "$file" ]; then
    echo "ERROR: both ${var} and ${file_var} are set (but are exclusive)" >&2
    return 1
  fi

  if [ -n "$file" ]; then
    if [ ! -r "$file" ]; then
      echo "ERROR: ${file_var} points to ${file}, which does not exist or is not readable" >&2
      return 1
    fi
    local value
    value="$(< "$file")"
    export "$var=$value"
  fi
  unset "$file_var"
}

# Resolve every supported NAME_FILE variable.
load_file_env() {
  local name
  for name in $PG_DOCKUP_FILE_ENV_VARS; do
    file_env "$name" || return 1
  done
}
