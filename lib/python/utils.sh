#!/usr/bin/env bash

# Namespace: python::

# ----- DETECTION ------------------------------------

# --- FUNCTION: python::find_binaries --- #
function python::find_binaries() {
  error::assert test -d /opt
  error::assert test -d /usr/bin
  error::assert test -d /usr/local/bin
  local search_roots=(/opt /usr/bin /usr/local/bin)
  find "${search_roots[@]}" \
    -maxdepth 3 \
    -type f \
    -executable \
    -regextype posix-extended \
    -regex ".*/python3\.[0-9]+$" 2> /dev/null
}

# --- FUNCTION: python::select_binary [min_ver:str] [max_ver:str] --- #
function python::select_binary() {
  error::require_args 2 "$@"
  local best best_version version py
  local min_version=$1
  local max_version=$2
  while IFS= read -r py; do
    version=$(python::version_from_binary "$py") || continue
    version=${version%.*}
    if [[ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n1)" != "$min_version" ]]; then
      continue
    fi
    if [[ "$(printf '%s\n' "$max_version" "$version" | sort -V | tail -n1)" != "$max_version" ]]; then
      continue
    fi
    if [[ -z "$best_version" ]] || [[ "$(printf '%s\n' "$best_version" "$version" | sort -V | tail -n1)" == "$version" ]]; then
      best="$py"
      best_version="$version"
    fi
  done < <(python::find_binaries)
  [[ -z "$best" ]] && return 1
  [[ -n "$best" ]] && printf "$best"
}

# --- FUNCTION: python::detect_conflicts [dir:str] [ver:str] --- #
function python::detect_conflicts() {
  error::require_args 2 "$@"
  local dir=$1
  local conflict_ver=$2
  local bin_path bin_ver entry maj min pat tmp
  [[ -d $dir ]] || {
    error::die "python::detect_conflicts() -> '$dir' does not exist"
  }
  for entry in "$dir"/*; do
    [[ -e $entry ]] || continue
    version=$(python::parse_version_string "${entry##*/}")
    bin_path="$(general::abspath $entry)/bin/python${version%.*}"
    bin_ver=$(python::version_from_binary "$bin_path")
    maj=${bin_ver%%.*}; tmp=${bin_ver#*.}; min=${tmp%%.*}; pat=${bin_ver##*.}
    if [[ $conflict_ver =~ ^(${maj})\.(${min})(\.${pat})?$ ]]; then
      printf "%s.%s.%s" "$maj" "$min" "${pat:-x}"
      return 1
    fi
  done
  return 0
}

# --- FUNCTION: python::get_version_from_binary [binary:str] --- #
function python::version_from_binary() {
  error::require_args 1 "$@"
  "$1" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2> /dev/null || return 1
}

# --- FUNCTION: python::version_lt [ver:str] [lt_ver:str] --- #
function python::version_lt() {
  error::require_args 2 "$@"
  [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]
}

# --- FUNCTION: python::parse_version_string [ver:str] --- #
function python::parse_version_string() {
  local ver=${1,,}
  if [[ $ver =~ ^python-?([0-9])\.([0-9]{1,2})(\.([0-9]{1,2}))?$ ]]; then
    printf "%s.%s.%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]:-0}"
    return 0
  fi
  return 1
}

# ----- GENERAL --------------------------------------

# --- FUNCTION: python::create_venv [binary:str] [dir:str] --- #
function python::create_venv() {
  error::require_args 2 "$@"
  local py=$1
  local dir=$2
  "$py" -m venv "$dir" > /dev/null 2>&1 || return 1
}

# ----- TESTING --------------------------------------

# --- FUNCTION: python::test_module [binary:str] [module:str] --- #
function python::test_module() {
  error::require_args 2 "$@"
  local py=$1
  local module=$2
  "$py" -c "import $module" > /dev/null 2>&1 || return 1
}

# --- FUNCTION: python::test_venv [binary:str] --- #
function python::test_venv() {
  error::require_args 1 "$@"
  local py=$1
  local test_dir=$(mktemp -d) || return 1
  trap "general::cleanup_dirs $test_dir" "${BSHT_VAR_TRAP_SIGNALS[@]}"
  "$py" -m venv "$test_dir" > /dev/null 2>&1 || return 1
  source "$test_dir/bin/activate" > /dev/null 2>&1 || return 1
  python -V > /dev/null 2>&1 || return 1
  deactivate > /dev/null 2>&1 || return 1
}

# ----- BUILDING -------------------------------------

# --- FUNCTION: python::install_build_dependencies --- #
function python::install_build_dependencies() {
  apt-get update -qq > /dev/null 2>&1 || return 1
  apt-get install -y -qq build-essential libssl-dev zlib1g-dev libncurses5-dev \
    libncursesw5-dev libreadline-dev libsqlite3-dev \
    libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev \
    liblzma-dev tk-dev libffi-dev xz-utils > /dev/null 2>&1 || return 1
}
