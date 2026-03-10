#!/usr/bin/env bash

# Namespace: log::

# ----- TERM COLOURS ---------------------------------

function log::setup_term_colours() {
  if [[ -t 1 ]]; then
    LOG_COLOUR_INFO="\033[1;37m"  # white bold
    LOG_COLOUR_WARN="\033[1;33m"  # yellow bold
    LOG_COLOUR_DEBUG="\033[1;34m" # blue bold
    LOG_COLOUR_ERROR="\033[1;31m" # red bold
    LOG_COLOUR_BLACK="\033[0;90m" # black high-intensity [looks like light gray]
    LOG_COLOUR_RESET="\033[0m"
  else
    LOG_COLOUR_INFO=""
    LOG_COLOUR_WARN=""
    LOG_COLOUR_DEBUG=""
    LOG_COLOUR_ERROR=""
    LOG_COLOUR_BLACK=""
    LOG_COLOUR_RESET=""
  fi
}

# ----- LOGGING --------------------------------------

# --- FUNCTION: _log [level:str] [msg:str].. --- #
function _log() {
  local level=$1; shift
  local ts
  local level_colour_var="LOG_COLOUR_$level"
  local level_colour=${!level_colour_var}
  if (( BSHT_FLAG_LOG_FILE_ENABLED )); then
    for msg in "${@:1}"; do
      ts=$(date '+%d-%m-%Y %H:%M:%S')
      [[ $level != "ERROR" && $level != "DEBUG" ]] && msg=" $msg"
      printf '[%s] [%s] %s\n' \
        "$ts" \
        "$level" \
        "$msg" >> "$BSHT_PATH_LOG_FILE"
    done
  fi
  if (( ! BSHT_FLAG_QUIET )) || [[ $level == "ERROR" ]]; then
    for msg in "${@:1}"; do
      ts=$(date '+%d-%m-%Y %H:%M:%S')
      [[ $level != "ERROR" && $level != "DEBUG" ]] && msg=" $msg"
      printf '[%b%s%b] [%b%s%b] %s\n' \
        "$LOG_COLOUR_BLACK" \
        "$ts" \
        "$LOG_COLOUR_RESET" \
        "$level_colour" \
        "$level" \
        "$LOG_COLOUR_RESET" \
        "$msg"
    done
  fi
}

# --- FUNCTION: infotext [msg:str].. --- #
function log::info() { _log INFO "$@"; }

# --- FUNCTION: warntext [msg:str].. --- #
function log::warn() { _log WARN "$@"; }

# --- FUNCTION: debugtext [msg:str].. --- #
function log::debug() { _log DEBUG "$@"; }

# --- FUNCTION: log_error [msg:str].. --- #
function log::error() { _log ERROR "$@" >&2; }
