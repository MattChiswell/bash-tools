#!/usr/bin/env bash

# ----- NOTES ----------------------------------------
# + variables prefixed with GLB_ are considered global
# + some GLB_ variables are mutated inside functions
#  - mutation was avoided except for:
#   - GLB_PATH_SWAPFILE
#   - GLB_FLAG_REDUCED_PERF
#   - GLB_FLAG_QUIET
# + very early versions will fail to configure/build
#   due to changes in expected build environment, you
#   will need to prepare your system manually before
#   attempting to install legacy versions (<= 3.4)
# ----------------------------------------------------

# ----- HELPERS --------------------------------------

usage() {
  echo ""
  echo "usage: $0 [OPTIONS]"
  echo "  options:"
  echo "    -d    install directory / prefix (/opt is recommended)"
  echo "    -u    python source file url (expects .tgz archive)"
  echo "    -v    python version number to download and install"
  echo "    -f    if install path does not exist, create it"
  echo "    -q    quite mode, dont output anything to terminal (except errors) and assume 'yes' for any prompts"
  echo "    -h    display this help text"
  echo "  info:"
  echo "    -d    always required"
  echo "    -u -v specifiy one, not both"
  echo "    -v    supports versions >= 2.0.1; ensure you use the exact version as specified on the official download server"
  echo "  versions:"
  echo "          versions 3.8 -> latest should have no issues building"
  echo "          versions 3.5 -> 3.7 may have some minor issues but will likely build"
  echo "          versions 3.3 -> 3.4 will require tweaking for a successful build"
  echo "          versions 3.0 -> 3.2 are often broken and will not build without patching"
  echo "          version 2.7 will often build but can be messy"
  echo "          versions <= 2.6 will require extensive patching"
  echo "          this script is intended to configure and build only"
  echo "          if you are trying to install a legacy version, no prior setup/patching will be done here, you must do this yourself"
  echo ""
  exit 1
}

exit_with_error() {
  printf "[ERROR] %s\n" "$@" >&2
  printf "[ERROR] see -h for help\n\n" >&2
  exit 1
}

infotext() {
  if ! (( GLB_FLAG_QUIET )); then
    printf "[INFO]  %s\n" "$@"
  fi
}

ask_confirmation() {
  if (( GLB_FLAG_QUIET )); then
    # assume yes
    return 0
  fi
  local prompt="$1"
  while true; do
    read -p "[INPUT] --> $prompt (y/n): " choice
    case "$choice" in
      [Yy]*)
        return 0
        ;;
      [Nn]*)
        return 1
        ;;
      *)
        echo "Invalid input. Please answer with 'y' or 'n'" >&2
        ;;
    esac
  done
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

version_lt() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" != "$2" ]
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
  apt-get update -qq > /dev/null || return 1
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
  infotext "cleaning up before exit.."
  if [[ -e $GLB_PATH_TMP_DIR ]]; then
    rm -r "$GLB_PATH_TMP_DIR"
    infotext "  --> removed '$GLB_PATH_TMP_DIR'"
  fi
  if [[ -e $GLB_PATH_INSTALL_TARGET ]] && (( $GLB_FLAG_DIR_CREATED )); then
    rm -r "$GLB_PATH_INSTALL_TARGET"
    infotext "  --> removed '$GLB_PATH_INSTALL_TARGET'"
  fi
  if [[ -e $GLB_PATH_SWAPFILE ]]; then
    swapoff "$GLB_PATH_SWAPFILE" > /dev/null 2>&1
    rm -f "$GLB_PATH_SWAPFILE"
    infotext "  --> disabled temporary swapfile and removed '$GLB_PATH_SWAPFILE'"
  fi
}

# ----- GLOBALS --------------------------------------

# Flags
GLB_FLAG_QUIET=0
GLB_FLAG_MKDIR=0
GLB_FLAG_DIR_CREATED=0
GLB_FLAG_REDUCED_PERF=0

# Vars
GLB_VAR_CORES=0
GLB_VAR_PY_VERSION=""

# URLs
GLB_URL_PY_SRC=""
GLB_URL_PY_SRC_BASE=""

# Paths
GLB_PATH_TARBALL=""
GLB_PATH_TMP_DIR=""
GLB_PATH_TMP_FILE=""
GLB_PATH_SWAPFILE=""
GLB_PATH_BUILD_DIR=""
GLB_PATH_BUILD_LOG=""
GLB_PATH_INSTALL_TARGET=""
GLB_PATH_INSTALL_PREFIX=""

# ----- ARGUMENTS ------------------------------------

while getopts d:u:v:fqh flag; do
  case "$flag" in
    d) GLB_PATH_INSTALL_TARGET="$OPTARG" ;;
    u) GLB_URL_PY_SRC="$OPTARG" ;;
    v) GLB_VAR_PY_VERSION="$OPTARG" ;;
    f) GLB_FLAG_MKDIR=1 ;;
    q) GLB_FLAG_QUIET=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

# ----- VALIDATION -----------------------------------

if [[ $EUID -ne 0 ]]; then
  (( GLB_FLAG_QUIET )) || echo -e "\nmust be run as root, retrying with sudo\n"
  exec sudo "$0" "$@"
fi

if [[ -z $GLB_PATH_INSTALL_TARGET ]]; then
  exit_with_error "missing argument: -d [PATH]"
fi

if [[ -z $GLB_URL_PY_SRC && -z $GLB_VAR_PY_VERSION ]]; then
  exit_with_error "missing argument: specify one of -u [URL] or -v [VERSION]"
fi

if [[ -n $GLB_URL_PY_SRC && -n $GLB_VAR_PY_VERSION ]]; then
  exit_with_error "too many arguments: specify one of -u [URL] OR -v [VERSION], not both"
fi

if ! [[ -d $GLB_PATH_INSTALL_TARGET ]] && ! (( $GLB_FLAG_MKDIR )); then
  exit_with_error "directory '$GLB_PATH_INSTALL_TARGET' does not exist, -f not set so will not create"
fi

# ----- SETUP ----------------------------------------

GLB_VAR_CORES=$(nproc)
GLB_PATH_TMP_DIR=$(mktemp -d) || exit_with_error "'mktemp' failed to create temporary directory in /tmp"
GLB_PATH_TMP_FILE=$(mktemp -u python.XXXXXX) || exit_with_error "'mktemp' failed to generate temporary filename"
GLB_PATH_BUILD_LOG=/var/log/py_build.log
GLB_PATH_TARBALL="${GLB_PATH_TMP_DIR}/${GLB_PATH_TMP_FILE}"
GLB_URL_PY_SRC_BASE="https://www.python.org/ftp/python/<PY_VER>/Python-<PY_VER>.tgz"

trap cleanup EXIT

# ----- RUN ------------------------------------------

# ----- INSTALL DIRECTORY -------------

if ! [[ -d $GLB_PATH_INSTALL_TARGET ]] && (( $GLB_FLAG_MKDIR )); then
  infotext "$GLB_PATH_INSTALL_TARGET does not exist, it will be created"
  mkdir -p "$GLB_PATH_INSTALL_TARGET"
  GLB_FLAG_DIR_CREATED=1
fi

# ----- DOWNLOAD/EXTRACT --------------

if [[ -z $GLB_URL_PY_SRC && -n $GLB_VAR_PY_VERSION ]]; then
  GLB_URL_PY_SRC=$(sed "s/<PY_VER>/${GLB_VAR_PY_VERSION}/g" <<< $GLB_URL_PY_SRC_BASE)
fi

infotext "this script will attempt to install Python from source"
infotext "download url: $GLB_URL_PY_SRC"
infotext "install path: $GLB_PATH_INSTALL_TARGET"
infotext "downloading archive, please wait.."

if ! download_file "$GLB_URL_PY_SRC" "$GLB_PATH_TARBALL"; then
  exit_with_error "download failed, please check the URL and try again"
fi

infotext "download complete" "extracting tarball.."
tar -xzf "$GLB_PATH_TARBALL" -C "$GLB_PATH_TMP_DIR"
infotext "extraction complete" "checking for conflicting versions in '$GLB_PATH_INSTALL_TARGET'.."

# ----- VERSION CONFLICTS -------------

if [[ -z $GLB_VAR_PY_VERSION ]]; then
  version_str=("$GLB_PATH_TMP_DIR"/*/)
  version_str=${version_str[0]%/}
  version_str=${version_str##*/}
  if ! GLB_VAR_PY_VERSION=$(parse_version_string "$version_str" | sed 's/ /./g'); then
    exit_with_error "unable to determine version number from downloaded Python tarball"
  fi
fi

if ! existing=$(detect_version_conflicts "$GLB_PATH_INSTALL_TARGET" "$GLB_VAR_PY_VERSION"); then
  echo "$existing"
  exit_with_error "unable to continue, change install path or remove existing version"
fi

GLB_PATH_BUILD_DIR=("$GLB_PATH_TMP_DIR"/*/)

# ----- INSTALL BUILD TOOLS -----------

infotext "no conflicts detected" "checking/installing build dependencies using apt.."
if ! install_build_dependencies; then
  exit_with_error "apt-get failed to install build dependencies"
fi
infotext "dependencies installed"

# ----- SYSTEM MEMORY/SWAP ------------

infotext "checking system memory setup" "a temporary swapfile may be created during this process, it will be removed automatically"
if ! check_build_memory; then
  infotext "a temporary swapfile was required due to the limited system memory available"
  exit_with_error "swapfile allocation failed" "cannot continue with current memory setup"
fi

# ----- CONFIGURE/BUILD ---------------

infotext "moving into build directory.." "  --> $GLB_PATH_BUILD_DIR"
cd "$GLB_PATH_BUILD_DIR"

# make install_prefix a global ?
install_prefix="${GLB_PATH_INSTALL_TARGET}/python${GLB_VAR_PY_VERSION%.*}"
infotext "configuring.." "  --enable-optimizations" "  --with-ensurepip=install" "  --prefix=$install_prefix"
if ! ./configure --enable-optimizations --with-ensurepip=install --prefix="$install_prefix" > "$GLB_PATH_BUILD_LOG" 2>&1; then
  infotext "'./configure' failed (exit code: $?)" "full build log will be shown below:"
  cat "$GLB_PATH_BUILD_LOG"
  exit 1
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

# ----- INSTALL -----------------------

infotext "build complete" "installing.."
if ! make altinstall > "$GLB_PATH_BUILD_LOG" 2>&1; then
  infotext "'make altinstall' failed (exit code: $?)" "full build log will be shown below:"
  cat "$GLB_PATH_BUILD_LOG"
  exit 1
fi

ln -s "${install_prefix}/bin/python${GLB_VAR_PY_VERSION%.*}" "${install_prefix}/bin/python3"

# ----- EXIT --------------------------

infotext "install complete" "Python binary is now available in '$GLB_PATH_INSTALL_TARGET'"
infotext "this version has NOT been added to your path"
exit 0
