#!/usr/local/env bash

# ----- BASH-TOOLS GLOBALS ---------------------------
# Namespace: BSHT_
#   -> BSHT_FLAG_QUIET
#   -> BSHT_PATH_LOG_FILE
#   -> BSHT_FLAG_LOG_FILE_ENABLED

# ----- TODOs ----------------------------------------
# TODO[0][x] - Flatten logfile functions
# TODO[1][ ] - Accept array of groups to generalise function
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

# ----- SERVICE/SYSCONFIG ----------------------------

# --- FUNCTION: create_service_user [user] --- #
# TODO[1][2]
util_create_service_user() {
  local user=$1
  local grps=(gpio i2c spi)
  if ! id "$user" > /dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$user" || return 1
  fi
  for grp in "${grps[@]}"; do
    if getent group "$grp" > /dev/null 2>&1; then
      if id "$user" | grep -q "$grp"; then
        continue
      fi
      usermod -aG "$grp" "$user" > /dev/null 2>&1 || return 1
    else
      return 1
    fi
  done
}

# --- FUNCTION: set_dtparam [dtparam] [state] [file] --- #
# TODO[2]
util_set_dtparam() {
  local param=$1
  local state=$2
  local file=$3
  if grep -q "^[[:space:]]*dtparam=${param}=${state}" "$file"; then
    # already set
    #echo "'${param}' already set to '${state}'"
    echo "STATE_1"
    return 0
  fi
  if grep -q "^[[:space:]]*#\?[[:space:]]*dtparam=${param}=" "$file"; then
    sed -i --follow-symlinks \
      "s/^[[:space:]]*#\?[[:space:]]*dtparam=${param}=.*/dtparam=${param}=${state}/" \
      "$file" || return 1
      # found and updated
      #echo "updated '${param}' to '${state}'"
      echo "STATE_2"
      return 0
  else
    echo "dtparam=${param}=${state}" >> "$file"
    # not found, added to EOF
    #echo "appended '${param}' with state '${state}' to end of '${file}'"
    echo "STATE_3"
    return 0
  fi
}

# --- FUNCTION: register_service [name] [template] [replacements] --- #
# TODO[2]
util_register_service() {
  local service_name=$1
  local template_file=$2
  local -n replacements=$3
  local service_file="/etc/systemd/system/${service_name}.service"
  [[ -e $service_file ]] && return 0
  sed \
    -e "s|%USER%|${replacements[0]}|g" \
    -e "s|%GROUP%|${replacements[1]}|g" \
    -e "s|%WORKINGDIR%|${replacements[2]}|g" \
    -e "s|%PYTHON%|${replacements[3]}|g" \
    -e "s|%APP%|${replacements[2]}/main.py|g" \
    -e "s|%RC522RESET%|${replacements[2]}/src/gpio/reset_rc522.sh|g" \
    "$template_file" > /dev/null 2>&1 || return 1
  mv "$template_file" "$service_file"
  systemctl daemon-reload > /dev/null 2>&1 || return 1
  systemctl enable "$service_name" > /dev/null 2>&1 || return 1
}

# --- FUNCTION: set_app_config [file] --- #
# TODO[2]
util_set_app_config() {
  local config_file=$1
  local -n out_webui_info=$2
  local log_levels=(DEBUG INFO WARN ERROR CRITICAL)
  ! [[ -f $config_file ]] && return 1
  echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Please enter desired config values, for defaults just press enter"
  read -p "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Database name [ca_att.db]: " input_db_name; input_db_name=${input_db_name:-ca_att.db}
  read -p "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Web server should listen on [0.0.0.0]: " input_web_host; input_web_host=${input_web_host:-0.0.0.0}
  read -p "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Web server port [8081]: " input_web_port; input_web_port=${input_web_port:-8081}
  read -p "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] RFID Reader RST GPIO pin [25]: " input_rfid_rst; input_rfid_rst=${input_rfid_rst:-25}
  read -p "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Enable logging to file? (y|n) [y]: " input_log_enabled; input_log_enabled=${input_log_enabled:-y}
  if [[ "$input_log_enabled" == "y" ]]; then
    read -p "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Logging level (DEBUG|INFO|WARN|ERROR|CRITICAL) [ERROR]: " input_log_level; input_log_level=${input_log_level:-ERROR}
    if ! util_array_contains log_levels "$input_log_level"; then
      echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Error: Log level must be one of DEBUG|INFO|WARN|ERROR|CRITICAL"
      echo "[$(date '+%d-%m-%Y %H:%M:%S')] [INPUT] Setting default value of 'ERROR'"
      input_log_level="ERROR"
    fi
  fi
  sed -i --follow-symlinks "s/sqlite_db.*/sqlite_db = ${input_db_name}/" "$config_file" || return 1
  sed -i --follow-symlinks "s/host.*/host = ${input_web_host}/" "$config_file" || return 1
  sed -i --follow-symlinks "s/port.*/port = ${input_web_port}/" "$config_file" || return 1
  sed -i --follow-symlinks "s/rst_pin.*/rst_pin = ${input_rfid_rst}/" "$config_file" || return 1
  if [[ "$input_log_enabled" == "y" ]]; then
    sed -i --follow-symlinks "s/enabled.*/enabled = True/" "$config_file" || return 1
    sed -i --follow-symlinks "s/level.*/level = ${input_log_level}/" "$config_file" || return 1
  fi
  out_webui_info=("$input_web_host" "$input_web_port")
}
