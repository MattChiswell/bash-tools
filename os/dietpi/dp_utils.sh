#!/usr/bin/env bash

# ----- BASH-TOOLS GLOBALS ---------------------------
# Namespace: BSHT_
#   -> BSHT_FLAG_QUIET
#   -> BSHT_PATH_LOG_FILE
#   -> BSHT_FLAG_LOG_FILE_ENABLED


# ----- SYSCONFIG ------------------------------------

# --- FUNCTION: set_dtparam [dtparam] [state] [file] --- #
util_set_dtparam() {
  local param=$1
  local state=$2
  local file=$3
  if grep -q "^[[:space:]]*dtparam=${param}=${state}" "$file"; then
    # already set
    echo "STATE_1"
    return 0
  fi
  if grep -q "^[[:space:]]*#\?[[:space:]]*dtparam=${param}=" "$file"; then
    sed -i --follow-symlinks \
      "s/^[[:space:]]*#\?[[:space:]]*dtparam=${param}=.*/dtparam=${param}=${state}/" \
      "$file" || return 1
      # found and updated
      echo "STATE_2"
      return 0
  else
    echo "dtparam=${param}=${state}" >> "$file"
    # not found, added to EOF
    echo "STATE_3"
    return 0
  fi
}
