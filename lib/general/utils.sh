#!/usr/bin/env bash

# Namespace: general::

# ----- INTERNAL -------------------------------------

# --- FUNCTION: general::require_root --- #
function general::require_root() {
  (( EUID == 0 )) && return
  (( BSHT_FLAG_NO_ROOT )) && return
  (( BSHT_FLAG_QUIET || BSHT_FLAG_SUPPRESS_ROOT_WARN )) || {
    log::warn "must be run as root, retrying with sudo"
    log::warn "enter sudo password if prompted"
  }
  local env_forward=()
  while IFS='=' read -r name value; do
    [[ $name == BSHT_* ]] && env_forward+=("$name=$value")
  done < <(env)
  exec sudo "${env_forward[@]}" "$0" "$@"
}

# --- FUNCTION: general::cleanup_dirs [dir:str].. --- #
function general::cleanup_dirs() {
  [[ $# -eq 0 ]] && return 0
  local dir
  for dir in "${@}"; do
    [[ -e $dir ]] || continue
    rm -r "$dir" > /dev/null 2>&1 || return 1
  done
  return 0
}

# ----- INPUT/OUTPUT ---------------------------------

# --- FUNCTION: general::ask_confirm [prompt:str] --- #
function general::ask_confirm() {
  (( BSHT_FLAG_QUIET )) && return 0
  local prompt=$1
  local ts=$(date '+%d-%m-%Y %H:%M:%S')
  local str
  if (( BSHT_FLAG_LOG_SIMPLE )); then
    str=$(printf '[%bINPUT%b] %s (y/n) ' \
      "$LOG_COLOUR_CYAN" \
      "$LOG_COLOUR_RESET" \
      "$prompt"
    )
  else
    str=$(printf '[%b%s%b] [%bINPUT%b] %s (y/n) ' \
      "$LOG_COLOUR_BLACK" \
      "$ts" \
      "$LOG_COLOUR_RESET" \
      "$LOG_COLOUR_CYAN" \
      "$LOG_COLOUR_RESET" \
      "$prompt"
    )
  fi
  while read -p "$str" response; do
    case "${response,,}" in
      y*) return 0 ;;
      n*) return 1 ;;
      *) log::warn "invalid response (y/n)"; return 2 ;;
    esac
  done
}

# --- FUNCTION: format_prompt [prompt:str] --- #
function general::format_prompt() {
  local prompt=$1
  local ts=$(date '+%d-%m-%Y %H:%M:%S')
  if (( BSHT_FLAG_LOG_SIMPLE )); then
    printf '[%bINPUT%b] %s: ' \
      "$LOG_COLOUR_CYAN" \
      "$LOG_COLOUR_RESET" \
      "$prompt"
  else
    printf '[%b%s%b] [%bINPUT%b] %s: ' \
      "$LOG_COLOUR_BLACK" \
      "$ts" \
      "$LOG_COLOUR_RESET" \
      "$LOG_COLOUR_CYAN" \
      "$LOG_COLOUR_RESET" \
      "$prompt"
  fi
}

# --- FUNCTION: infoheader [title:str] --- #
function general::infoheader() {
  (( BSHT_FLAG_QUIET )) && return 0
  local text="${1^^}"
  local width=80
  local pad="-"
  local len=${#text}
  local pad_total=$(( width - len - 2 ))
  (( pad_total < 0 )) && pad_total=0
  local left=$(( pad_total / 2 ))
  local right=$(( pad_total - left ))
  printf '\n%b%s %s %s%b\n\n' \
    "$LOG_COLOUR_GREEN" \
    "$(printf "%*s" "$left" | tr ' ' "$pad")" \
    "$text" \
    "$(printf "%*s" "$right" | tr ' ' "$pad")" \
    "$LOG_COLOUR_RESET"
}

# --- FUNCTION: infodivider --- #
function general::infodivider() {
  (( BSHT_FLAG_QUIET )) && return 0
  printf \
    "\n%b--------------------------------------------------------------------%b\n\n" \
    "$LOG_COLOUR_GREEN" \
    "$LOG_COLOUR_RESET"
}

# ----- VALIDATION -----------------------------------

# --- FUNCTION: general::array_contains [source:array] [search_term:str] --- #
function general::array_contains() {
  error::require_args 2 "$@"
  local -n array=$1
  local search=$2
  for item in "${array[@]}"; do
    [[ $item == $search ]] && return 0
  done
  return 1
}

# ----- FILESYSTEM -----------------------------------

# --- FUNCTION: general::abspath [path:str] --- #
function general::abspath() {
  error::require_args 1 "$@"
  if command -v realpath > /dev/null 2>&1; then
    realpath "$1" 2> /dev/null || return 1
    return 0
  elif command -v readlink > /dev/null 2>&1; then
    readlink -f "$1" 2> /dev/null || return 1
    return 0
  else
    printf '%s\n' "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
    return 0
  fi
}

# --- FUNCTION: general::is_empty_dir [path:str] --- #
function general::is_empty_dir() {
  error::require_args 1 "$@"
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

# --- FUNCTION: general::download_file [url:str] [dest:str] --- #
function general::download_file() {
  error::require_args 2 "$@"
  local url=$1
  local dest=$2
  if command -v curl > /dev/null 2>&1; then
    curl -fsL "$url" -o "$dest" || return 1
  elif command -v wget > /dev/null 2>&1; then
    wget -q -O "$dest" "$url" || return 1
  else
    error::die "neither 'curl' nor 'wget' could be found, please install one of these and try again"
  fi
}

# ----- SYSTEM ---------------------------------------

# --- FUNCTION: general::check_disk_space [path:str] [req_space:int] [buffer:int] --- #
function general::check_disk_space() {
  error::require_args 2 "$@"
  # all sizes are KB
  local path=$1
  local req_space_kb=$2
  local req_space_buff=${3:-0}
  local req_space=$(( $req_space_kb + $req_space_buff ))
  local available_kb=$(df -Pk "$path" | awk 'NR==2 {print $4}')
  [[ $available_kb -lt $req_space ]] && return 1
  return 0
}

# --- FUNCTION: general::check_memory [include_swap:int] --- #
function general::check_memory() {
  # all sizes are KB
  local include_swap=${1:-0}
  local total_ram=$(cat /proc/meminfo | grep 'MemTotal' | grep -o '[0-9]\+') || return 1
  local total_swp=$(cat /proc/meminfo | grep 'SwapTotal' | grep -o '[0-9]\+') || return 1
  local total_mem
  (( include_swap )) && total_mem=$(( $total_ram + $total_swp ))
  (( ! include_swap )) && total_mem=$(( $total_ram ))
  printf "$total_mem"
  return 0
}

# --- FUNCTION: general::create_swap [swapsize:int] [swapfile:str] --- #
function general::create_swap() {
  error::require_args 2 "$@"
  # all sizes are KB
  local swapsize=$1
  local swapfile=$2
  if ! general::check_disk_space "${swapfile%/*}" "$swapsize" 102400; then
    # consider throwing warning here and maybe letting the caller reduce size by 25% and try again?
    error::die "insufficient free space in '${swapfile%/*}' for temporary swapfile, cannot continue"
  fi
  fallocate -l "${swapsize}K" "$swapfile" > /dev/null 2>&1 || return 1
  chmod 600 "$swapfile"
  mkswap "$swapfile" > /dev/null 2>&1 || return 1
  swapon "$swapfile" > /dev/null 2>&1 || return 1
}

# --- FUNCTION: general::remove_swap [swapfile:str] --- #
function general::remove_swap() {
  error::require_args 1 "$@"
  local swapfile=$1
  [[ -e $swapfile ]] || return 0
  swapoff "$swapfile" > /dev/null 2>&1 || return 1
  rm "$swapfile" > /dev/null 2>&1 || return 1
}

# ----- SYSTEM ---------------------------------------

# --- FUNCTION: general::create_system_user [user:str] [groups:array] [array(out)] --- #
function general::create_system_user() {
  error::require_args 1 "$@"
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
