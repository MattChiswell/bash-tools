#!/usr/bin/env bash


# ----- SYSCONFIG ------------------------------------

# --- FUNCTION: set_dtparam [dtparam:str] [state:str] [file:str] --- #
function os::dietpi::set_dtparam() {
  local param=$1
  local state=$2
  local file=$3
  if grep -q "^[[:space:]]*dtparam=${param}=${state}" "$file"; then
    # already set
    printf "STATE_1"
    return 0
  fi
  if grep -q "^[[:space:]]*#\?[[:space:]]*dtparam=${param}=" "$file"; then
    sed -i --follow-symlinks \
      "s/^[[:space:]]*#\?[[:space:]]*dtparam=${param}=.*/dtparam=${param}=${state}/" \
      "$file" || return 1
      # found and updated
      printf "STATE_2"
      return 0
  else
    printf "dtparam=${param}=${state}" >> "$file"
    # not found, added to EOF
    printf "STATE_3"
    return 0
  fi
}
