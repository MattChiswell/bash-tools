#!/usr/bin/env bash

# Namespace: error::

# ----- ERROR HANDLING -------------------------------

# --- FUNCTION: error::die [msg:str] --- #
function error::die() {
  log::error "$1"
  (( BSHT_FLAG_DEBUG )) && error::stacktrace
  exit "${2:-1}"
}

# --- FUNCTION: error::try [cmd opts args] --- #
function error::try() {
  local out status
  out=$("$@" 2>&1)
  status=$?
  (( status == 0 )) && return 0
  log::error "command failed ($status): $*"
  if (( BSHT_FLAG_DEBUG )) && [[ -n $out ]]; then
    log::debug "stderr from: $*"
    printf '%s\n' "$out" | sed 's/^/  /' >&2
  else
    log::error "enable debug output to see more info"
  fi
  return "$status"
}

# --- FUNCTION: error::assert [test opts args] --- #
function error::assert() {
  "$@" && return 0
  printf '[ASSERT] %s:%s: %s\n' \
    "${BASH_SOURCE[1]}" \
    "${BASH_LINENO[0]}" \
    "$*" >&2
  exit 1
}

# --- FUNCTION: error::require [cmd:str].. --- #
# should we die here instead? less clutter in the caller?
function error::require() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" > /dev/null 2>&1 || {
      log::error "required command not found: $cmd"
      return 1
    }
  done
}

# --- FUNCTION: error::require_args [required:int] [actual:int] --- #
function error::require_args() {
  local expected=$1
  shift
  (( $# >= expected )) || error::die "expected $expected arguments, got $#"
}

# --- FUNCTION: error::stacktrace --- #
function error::stacktrace() {
  local i
  for ((i=${#FUNCNAME[@]}-1; i>=1; i--)); do
    printf '  at %s (%s:%s)\n' \
      "${FUNCNAME[$i]}" \
      "${BASH_SOURCE[$i]}" \
      "${BASH_LINENO[$((i-1))]}" >&2
  done
}
