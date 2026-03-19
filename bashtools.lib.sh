#!/usr/bin/env bash

# ----- BASH-TOOLS GLOBALS ---------------------------
# Namespace: BSHT_
#   -> BSHT_LIB_LOADED
#   -> BSHT_PATH_ROOT_DIR
#   -> BSHT_PATH_LOG_FILE
#   -> BSHT_FLAG_QUIET
#   -> BSHT_FLAG_DEBUG
#   -> BSHT_FLAG_LOG_FILE_ENABLED
#   -> BSHT_VAR_TRAP_SIGNALS
# ----------------------------------------------------

# ----- BASH CHECK -----------------------------------

if [[ ${BASH_VERSINFO:-0} -lt 4 ]]; then
    printf "This script requires Bash >= 4.3\n" >&2
    printf "Detected version: $BASH_VERSION\n" >&2
    exit 1
fi

# ----- INIT -----------------------------------------

# Prevent double loading
[[ ${BSHT_LIB_LOADED:-0} == 1 ]] && return
BSHT_LIB_LOADED=1

# ----- GLOBALS --------------------------------------

# Paths
BSHT_PATH_ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)

# Default configuration
BSHT_FLAG_QUIET=${BSHT_FLAG_QUIET:-0}
BSHT_FLAG_DEBUG=${BSHT_FLAG_DEBUG:-0}
BSHT_FLAG_LOG_FILE_ENABLED=${BSHT_FLAG_LOG_FILE_ENABLED:-0}
BSHT_PATH_LOG_FILE=${BSHT_PATH_LOG_FILE:-${BSHT_PATH_ROOT_DIR}/bsht_output.log}
BSHT_VAR_TRAP_SIGNALS=(EXIT HUP INT QUIT ABRT KILL TERM STOP)

# ----- LOAD LIBS ------------------------------------

source "${BSHT_PATH_ROOT_DIR}/lib/core/logging.sh"
source "${BSHT_PATH_ROOT_DIR}/lib/core/error.sh"
source "${BSHT_PATH_ROOT_DIR}/lib/general/utils.sh"
source "${BSHT_PATH_ROOT_DIR}/lib/python/utils.sh"
source "${BSHT_PATH_ROOT_DIR}/lib/os/dietpi/utils.sh"

# ----- SETUP ----------------------------------------

# Terminal error/warn colouring
log::setup_term_colours

# Ensure we run as root
general::require_root "$@"
