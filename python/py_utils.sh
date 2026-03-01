#!/usr/bin/env bash

# ----- INFO ---------------------------
# Namespace: py_util_

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

# --- FUNCTION: get_version_from_binary [binary] --- #
py_util_get_version_from_binary() {
  "$1" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' > /dev/null 2>&1 || return 1
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

# ----- TESTING --------------------------------------

# --- FUNCTION: test_module [binary] [module] --- #
py_util_test_module() {
  local py=$1
  local module=$2
  "$py" -c "import $module" > /dev/null 2>&1 || return 1
}

# --- FUNCTION: test_venv [binary] --- #
py_util_test_venv() {
  local py=$1
  local test_dir=$(mktemp -d) || return 1
  "$py" -m venv "$test_dir" > /dev/null 2>&1 || return 1
  source "$test_dir/bin/activate" > /dev/null 2>&1 || return 1
  python -V > /dev/null 2>&1 || return 1
  deactivate > /dev/null 2>&1 || return 1
  rm -r "$test_dir"
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
