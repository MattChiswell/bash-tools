#!/usr/bin/env bash

# ----- INCLUDES -------------------------------------

# setup script path early
PY_UTIL_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd -P)

# load required scripts
source "${PY_UTIL_SCRIPT_DIR%/*}/general/utils.sh"

# ----- DETECTION ------------------------------------

# --- FUNCTION: scan_directory [dir] --- #
py_util_scan_directory() {
  local dir=$1
  local entry name
  for entry in "$dir"/*; do
    [[ -e $entry ]] || continue
    name=${entry##*/}
    py_util_parse_version_string "$name"
  done
}

# --- FUNCTION: version_lt [ver] [lt_ver] --- #
py_util_version_lt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]
}

# --- FUNCTION: parse_version_string [ver] --- #
py_util_parse_version_string() {
  local version_str=${1,,}  # make lowercase
  if [[ $version_str =~ ^python-?([0-9])\.([0-9]{1,2})(\.([0-9]{1,2}))?$ ]]; then
    printf '%s %s %s\n' \
      "${BASH_REMATCH[1]}" \
      "${BASH_REMATCH[2]}" \
      "${BASH_REMATCH[4]:-0}"
    return 0
  fi
  return 1
}

# --- FUNCTION: detect_version_conflicts [dir] [ver] --- #
py_util_detect_version_conflicts() {
  local dir=$1
  local conflict_ver=${2%.*}
  local maj min pat
  while read -r maj min pat; do
    if [[ "${maj}.${min}" == $conflict_ver ]]; then
      util_infotext "conflicting version (python${maj}.${min}) detected in '$dir'"
      util_infotext "installing python${conflict_ver} in the same directory is not possible"
      return 1
    fi
  done < <(py_util_scan_directory "$dir")
}

# ----- BUILDING -------------------------------------

# --- FUNCTION: install_build_dependencies --- #
py_util_install_build_dependencies() {
  apt-get update -qq > /dev/null || return 1
  apt-get install -y -qq build-essential libssl-dev zlib1g-dev libncurses5-dev \
    libncursesw5-dev libreadline-dev libsqlite3-dev \
    libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev \
    liblzma-dev tk-dev libffi-dev xz-utils > /dev/null || return 1
}

# --- FUNCTION: build_swap [swapfile] --- #
py_util_build_swap() {
  local swapfile=$1
  local total_mem=$(util_check_memory) || return 1
  if [[ $total_mem -lt 1048576 ]]; then
    # 3G swap
    echo "PERF_1"
    if ! util_create_swap 3145728 "$swapfile"; then
      return 1
    fi
  elif [[ $total_mem -gt 1048576 && $total_mem -lt 2097152 ]]; then
    # 2G swap
    echo "PERF_1"
    if ! util_create_swap 2097152 "$swapfile"; then
      return 1
    fi
  elif [[ $total_mem -gt 2097152 && $total_mem -lt 3145728 ]]; then
    # 1G swap
    if ! util_create_swap 1048576 "$swapfile"; then
      return 1
    fi
  elif [[ $total_mem -gt 3145728 ]]; then
    # no extra swap needed
    echo "PERF_2"
    return 0
  else
    # failure somewhere
    return 1
  fi
}
