#!/usr/bin/env bash

# ----- BASH-TOOLS GLOBALS ---------------------------
# Namespace: BSHT_
#   -> BSHT_FLAG_QUIET
#   -> BSHT_PATH_LOG_FILE
#   -> BSHT_FLAG_LOG_FILE_ENABLED

# ----- TODOs ----------------------------------------
# TODO[0][x] - Flatten logfile functions
# TODO[1][x] - Accept array of groups to generalise function
# TODO[2][ ] - Consider moving these to seperate file
# TODO[3][x] - Refactor the mem check into its own function


# ----- INPUT/OUTPUT ---------------------------------

# --- FUNCTION: _log [level] [msg..] --- #
_log() {
  local level=$1; shift
  local ts
  if (( BSHT_FLAG_LOG_FILE_ENABLED )); then
    for msg in "${@:1}"; do
      ts=$(date '+%d-%m-%Y %H:%M:%S')
      [[ $level != "ERROR" ]] && msg=" $msg"
      printf '[%s] [%s] %s\n' "$ts" "$level" "$msg" >> "$BSHT_PATH_LOG_FILE"
    done
  fi
  if (( ! BSHT_FLAG_QUIET )) || [[ $level == "ERROR" ]]; then
    for msg in "${@:1}"; do
      ts=$(date '+%d-%m-%Y %H:%M:%S')
      [[ $level != "ERROR" ]] && msg=" $msg"
      printf '[%s] [%s] %s\n' "$ts" "$level" "$msg"
    done
  fi
}

# --- FUNCTION: infotext [msg..] --- #
util_infotext() { _log INFO "$@"; }

# --- FUNCTION: warntext [msg..] --- #
util_warntext() { _log WARN "$@"; }

# --- FUNCTION: log_error [msg..] --- #
util_log_error() { _log ERROR "$@" >&2; }

# --- FUNCTION: exit_with_error [msg..] --- #
util_exit_with_error() {
  util_log_error "$@"
  util_log_error "see -h for help"
  echo ""
  exit 1
}

# --- FUNCTION: infoheader [title] --- #
util_infoheader() {
  (( BSHT_FLAG_QUIET )) && return 0
  local text="${1^^}"
  local width=80
  local pad="-"
  local len=${#text}
  local pad_total=$(( width - len - 2 ))
  (( pad_total < 0 )) && pad_total=0
  local left=$(( pad_total / 2 ))
  local right=$(( pad_total - left ))
  printf '\n%s %s %s\n\n' \
    "$(printf "%*s" "$left" | tr ' ' "$pad")" \
    "$text" \
    "$(printf "%*s" "$right" | tr ' ' "$pad")"
}

# --- FUNCTION: infodivider --- #
util_infodivider() {
  (( BSHT_FLAG_QUIET )) && return 0
  printf "\n--------------------------------------------------------------------\n\n"
}

# --- FUNCTION: ask_confirm [prompt] --- #
util_ask_confirm() {
  (( BSHT_FLAG_QUIET )) && return 0
  local prompt=$1
  while read -p "[] [INPUT] $prompt (y|n) " response; do
    case "${response,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) util_warntext "invalid response (y|n)" ;;
    esac
  done
}

# ----- INTERNAL -------------------------------------

# --- FUNCTION: array_contains [source_array] [search_term] --- #
util_array_contains() {
  local -n array=$1
  local search=$2
  for item in "${array[@]}"; do
    if [[ "$item" == "$search" ]]; then
      # found
      return 0
    fi
  done
  # not found
  return 1
}

# ----- FILESYSTEM -----------------------------------

# --- FUNCTION: is_empty_dir [path] --- #
util_is_empty_dir() {
  local dir=$1
  [[ -d $dir ]] || return 1
  local nullglob dotglob
  nullglob=$(shopt -p nullglob)
  dotglob=$(shopt -p dotglob)
  shopt -s nullglob dotglob
  local files=("$dir"/*)
  shopt -u nullglob dotglob
  eval "$nullglob"
  eval "$dotglob"
  (( ${#files[@]} == 0 ))
}

# --- FUNCTION: download_file [url] [dest] --- #
util_download_file() {
  local url=$1
  local dest=$2
  if [[ -z $url || -z $dest ]]; then
    util_exit_with_error "download_file() called but not passed required argument(s)"
  fi
  if command -v curl > /dev/null 2>&1; then
    util_infotext "curl: attempting to download '$url' into '$dest'.."
    if ! curl -fsL "$url" -o "$dest"; then
      return 1
    fi
  elif command -v wget > /dev/null 2>&1; then
    util_infotext "wget: attempting to download '$url' into '$dest'.."
    if ! wget -q -O "$dest" "$url"; then
      return 1
    fi
  else
    util_exit_with_error "neither 'curl' nor 'wget' could be found, please install one of these and try again"
  fi
}

# ----- SYSTEM ---------------------------------------

# --- FUNCTION: check_disk_space [path] [req_space] [buffer] --- #
util_check_disk_space() {
  # all sizes are KB
  local path=$1
  local req_space_kb=$2
  local req_space_buff=${3:-0}
  local req_space=$(( $req_space_kb + $req_space_buff ))
  local available_kb=$(df -Pk "$path" | awk 'NR==2 {print $4}')
  [[ $available_kb -lt $req_space ]] && return 1
  return 0
}

# --- FUNCTION: check_memory --- #
util_check_memory() {
  # all sizes are KB
  local total_ram=$(cat /proc/meminfo | grep 'MemTotal' | grep -o '[0-9]\+') || return 1
  local total_swp=$(cat /proc/meminfo | grep 'SwapTotal' | grep -o '[0-9]\+') || return 1
  local total_mem=$(( $total_ram + $total_swp ))
  echo "$total_mem"
  return 0
}

# --- FUNCTION: create_swap [swapsize] [swapfile] --- #
util_create_swap() {
  # all sizes are KB
  local swapsize=$1
  local swapfile=$2
  if ! util_check_disk_space "${swapfile%/*}" "$swapsize" 512000; then
    echo "insufficient free space in '${swapfile%/*}' for temporary swapfile, cannot continue"
    exit 1
  fi
  fallocate -l "${swapsize}K" "$swapfile" > /dev/null || return 1
  chmod 600 "$swapfile"
  mkswap "$swapfile" > /dev/null || return 1
  swapon "$swapfile" > /dev/null || return 1
}

# ----- SOFTWARE/PACKAGES ----------------------------

# --- FUNCTION: check_command [command] --- #
util_check_command() {
  if command -v "$1" > /dev/null; then
    return 0
  fi
  return 1
}

# ----- SYSTEM ---------------------------------------

# --- FUNCTION: create_system_user [user:str] [groups:array] [array(out)] --- #
util_create_system_user() {
  local user=$1
  [[ -n $2 ]] && local -n groups=$2
  [[ -n $3 ]] && local -n not_found=$3
  if ! id "$user" > /dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$user" || return 1
  fi
  [[ -z $groups ]] && return 0
  for grp in "${groups[@]}"; do
    if getent group "$grp" > /dev/null 2>&1; then
      if id "$user" | grep -q "$grp"; then
        continue
      fi
      usermod -aG "$grp" "$user" > /dev/null 2>&1 || return 1
    else
      not_found+=("$grp")
      continue
    fi
  done
}
