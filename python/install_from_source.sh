#!/usr/bin/env bash

# ----- NOTES ----------------------------------------
# + variables prefixed with GLB_ are considered global
# + some GLB_ variables are mutated inside functions
#  - random mutation was avoided except for:
#   - GLB_PATH_SWAPFILE
#   - GLB_FLAG_REDUCED_PERF
# ----------------------------------------------------

# ----- ROOT -----------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo -e "\nmust be run as root, retrying with sudo\n"
  exec sudo "$0" "$@"
fi

# ----- HELPERS --------------------------------------

usage() {
  echo ""
  echo "usage: $0 [OPTIONS]"
  echo "  options:"
  echo "    -d    install directory / prefix"
  echo "    -u    python source file url (expects .tgz archive)"
  echo "    -f    if install path does not exist, create it"
  echo "    -h    display this help text"
  echo ""
  exit 1
}

exit_with_error() {
  printf "[ERROR] %s\n" "$@" >&2
  printf "[ERROR] see -h for help\n\n" >&2
  exit 1
}

infotext() {
  printf "[INFO]  %s\n" "$@"
}

scan_directory() {
  local dir="$1"
  local entry name
  for entry in "$dir"/*; do
    [[ -e $entry ]] || continue
    name=${entry##*/}
    parse_version_string "$name"
  done
}

parse_version_string() {
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

detect_version_conflicts() {
  local dir="$1"
  local conflict_ver="${2%.*}"
  local maj min pat
  while read -r maj min pat; do
    if [[ "${maj}.${min}" == $conflict_ver ]]; then
      infotext "conflicting version (python${maj}.${min}.${pat}) detected in '$dir'"
      infotext "installing python${conflict_ver} in the same directory is not possible"
      return 1
    fi
  done < <(scan_directory "$dir")
}

download_file() {
  local url="$1"
  local dest="$2"
  if [[ -z $url || -z $dest ]]; then
    exit_with_error "download_file() called but not passed required argument(s)"
  fi
  if command -v curl > /dev/null 2>&1; then
    infotext "curl: attempting to download '$url' into '$dest'.."
    if ! curl -fsL "$url" -o "$dest"; then
      return 1
    fi
  elif command -v wget > /dev/null 2>&1; then
    infotext "wget: attempting to download '$url' into '$dest'.."
    if ! wget -q -O "$dest" "$url"; then
      return 1
    fi
  else
    exit_with_error "neither 'curl' nor 'wget' could be found, please install one of these and try again"
  fi
}

install_build_dependencies() {
  apt-get update -qq || return 1
  apt-get install -y -qq build-essential libssl-dev zlib1g-dev libncurses5-dev \
    libncursesw5-dev libreadline-dev libsqlite3-dev \
    libgdbm-dev libdb5.3-dev libbz2-dev libexpat1-dev \
    liblzma-dev tk-dev libffi-dev xz-utils > /dev/null || return 1
}

check_disk_space() {
  # all sizes are KB
  local path="$1"
  local req_space_kb="$2"
  local req_space_buff=${3:-0}
  local req_space=$(( $req_space_kb + $req_space_buff ))
  local available_kb=$(df -Pk "$path" | awk 'NR==2 {print $4}')
  if [[ $available_kb -lt $req_space ]]; then
    return 1
  fi
  return 0
}

check_build_memory() {
  # all sizes are KB
  local total_ram=$(cat /proc/meminfo | grep 'MemTotal' | grep -o '[0-9]\+')
  local total_swp=$(cat /proc/meminfo | grep 'SwapTotal' | grep -o '[0-9]\+')
  local total_mem=$(( $total_ram + $total_swp ))
  if [[ $total_mem -lt 1048576 ]]; then
    # 3G swap
    GLB_FLAG_REDUCED_PERF=1
    if ! create_swap 3145728; then
      return 1
    fi
  elif [[ $total_mem -gt 1048576 && $total_mem -lt 2097152 ]]; then
    # 2G swap
    GLB_FLAG_REDUCED_PERF=1
    if ! create_swap 2097152; then
      return 1
    fi
  elif [[ $total_mem -gt 2097152 && $total_mem -lt 4194304 ]]; then
    # 1G swap
    if ! create_swap 1048576; then
      return 1
    fi
  elif [[ $total_mem -gt 4194304 ]]; then
    # no extra swap needed
    return 0
  else
    # failure somewhere
    return 1
  fi
  # success
  return 0
}

create_swap() {
  # all sizes are KB
  local swapsize="$1"
  local swapdir=/var
  GLB_PATH_SWAPFILE="${swapdir}/py_build_swap"
  if ! check_disk_space "$swapdir" "$swapsize" 512000; then
    exit_with_error "insufficient free space in '$swapdir' for temporary swapfile, cannot continue"
  fi
  fallocate -l "${swapsize}K" "$GLB_PATH_SWAPFILE" > /dev/null || return 1
  chmod 600 "$GLB_PATH_SWAPFILE"
  mkswap "$GLB_PATH_SWAPFILE" > /dev/null || return 1
  swapon "$GLB_PATH_SWAPFILE" > /dev/null || return 1
}

remove_swap() {
  swapoff "$GLB_PATH_SWAPFILE" > /dev/null || return 1
  rm -f "$GLB_PATH_SWAPFILE"
}

cleanup() {
  echo ""
  infotext "cleaning up before exit.." "  --> removing temporary swapfile (if present).." "  --> removing build directory.."
  if [[ -e $GLB_PATH_TMP_DIR ]]; then
    rm -r "$GLB_PATH_TMP_DIR"
    infotext "  --> removed '$GLB_PATH_TMP_DIR'"
  fi
  if [[ -e $GLB_PATH_SWAPFILE ]]; then
    swapoff "$GLB_PATH_SWAPFILE" > /dev/null 2>&1
    rm -f "$GLB_PATH_SWAPFILE"
    infotext "  --> disabled temporary swapfile and removed '$GLB_PATH_SWAPFILE'"
  fi
}

# ----- GLOBALS --------------------------------------

# Flags
GLB_FLAG_MKDIR=0
GLB_FLAG_REDUCED_PERF=0

# Vars
GLB_VAR_CORES=0
GLB_VAR_PY_SRC_URL=""
GLB_VAR_PY_VERSION=""

# Paths
GLB_PATH_TARBALL=""
GLB_PATH_TMP_DIR=""
GLB_PATH_TMP_FILE=""
GLB_PATH_SWAPFILE=""
GLB_PATH_BUILD_DIR=""
GLB_PATH_BUILD_LOG=""
GLB_PATH_INSTALL_TARGET=""

# ----- ARGUMENTS ------------------------------------

while getopts d:u:fh flag; do
  case "$flag" in
    d) GLB_INSTALL_PATH="$OPTARG" ;;
    u) GLB_PYTHON_SRC_URL="$OPTARG" ;;
    f) GLB_FLAG_MKDIR=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

# ----- VALIDATION -----------------------------------

if [[ -z $GLB_INSTALL_PATH || -z $GLB_PYTHON_SRC_URL ]]; then
  exit_with_error "missing argument(s)"
fi

if ! [[ -d $GLB_INSTALL_PATH ]] && ! (( $GLB_FLAG_MKDIR )); then
  exit_with_error "directory '$GLB_INSTALL_PATH' does not exist, -f not set so will not create"
fi

# ----- RUN ------------------------------------------

infotext "this script will attempt to install Python from source"
infotext "download url: $GLB_PYTHON_SRC_URL"
infotext "install path: $GLB_INSTALL_PATH"
infotext "downloading archive, please wait.."

GLB_TEMP_DL_PATH=$(mktemp -d) || exit_with_error "mktemp failed to create tempdir"
GLB_TEMP_DL_FILE=$(mktemp -u python.XXXXXX) || exit_with_error "mktemp failed to create tempfile"
GLB_TEMP_TARBALL="${GLB_TEMP_DL_PATH}/${GLB_TEMP_DL_FILE}"

trap cleanup EXIT

#trap "rm -rf '$GLB_TEMP_DL_PATH'" EXIT
if ! download_file $GLB_PYTHON_SRC_URL $GLB_TEMP_TARBALL; then
  exit_with_error "download failed, please check the URL and try again"
fi

infotext "download complete" "extracting tarball.."
tar -xzf "$GLB_TEMP_TARBALL" -C "$GLB_TEMP_DL_PATH"
folder=$(ls "$GLB_TEMP_DL_PATH" | grep -oE "$GLB_REGEX_PY_TARBALL")
py_full_version=$(sed "s/Python-//" <<< "$folder")
detected=$(ls "$GLB_INSTALL_PATH" | grep -oE "$GLB_REGEX_PY_BIN" | sed "s/python//")

infotext "extraction complete" "checking for conflicting versions in '$GLB_INSTALL_PATH'.."
if match=$(grep -Fx "${py_full_version%.*}" <<< "$detected"); then
  infotext "version conflict detected" "python${match} was detected in '$GLB_INSTALL_PATH'" "you are trying to install python${py_full_version}"
  exit_with_error "cannot install matching major version in this directory" "remove existing version or change install path and try again"
fi

infotext "checking/installing build dependencies using apt.."
if ! install_build_dependencies; then
  exit_with_error "apt-get failed to install build dependencies"
fi
infotext "dependencies installed"

infotext "checking system memory setup" "a temporary swapfile may be created during this process, it will be removed automatically"
if ! check_build_memory; then
  infotext "a temporary swapfile was required due to the limited system memory available"
  exit_with_error "swapfile allocation failed" "cannot continue with current memory setup"
fi

infotext "moving into source directory.." "  --> ${GLB_TEMP_DL_PATH}/${folder}"
cd "${GLB_TEMP_DL_PATH}/${folder}"

infotext "configuring.." "  --enable-optimizations" "  --with-ensurepip=install" "  --prefix=$GLB_INSTALL_PATH"
install_prefix="${GLB_INSTALL_PATH}/python${py_full_version%.*}"
if ! ./configure --enable-optimizations --with-ensurepip=install --prefix=$install_prefix > /dev/null; then
  exit_with_error "./configure failed to complete, exit code: $?"
fi

infotext "configure complete" "note that building may take +1hr on limited hardware"
infotext "all build output is redirected into '$GLB_PATH_BUILD_LOG'" "building.."
if (( $GLB_FLAG_REDUCED_PERF )); then
  GLB_VAR_CORES=2
fi
if ! make -j${GLB_VAR_CORES} > "$GLB_PATH_BUILD_LOG" 2>&1; then
  infotext "'make' failed (exit code: $?)" "full build log will be shown below:"
  cat "$GLB_PATH_BUILD_LOG"
  exit 1
fi

infotext "build complete" "installing.."
if ! make altinstall > "$GLB_PATH_BUILD_LOG" 2>&1; then
  infotext "'make altinstall' failed (exit code: $?)" "full build log will be shown below:"
  cat "$GLB_PATH_BUILD_LOG"
  exit 1
fi

infotext "install complete" "Python binary is now available in '$GLB_INSTALL_PATH'"
infotext "this version has NOT been added to your path"
exit 0
