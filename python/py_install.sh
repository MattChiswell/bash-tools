#!/usr/bin/env bash

# ----- NOTES ----------------------------------------
# + variables prefixed with PYI_ are considered global
# + external mutation of globals should be avoided
# + very early versions will fail to configure/build
#   due to changes in expected build environment, you
#   will need to prepare your system manually before
#   attempting to install legacy versions (<= 3.4)
# ----------------------------------------------------

# ----- INCLUDES -------------------------------------

# setup script path early
PYI_PATH_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# load required scripts
source "${PYI_PATH_SCRIPT_DIR%/*}/general/utils.sh"
source "${PYI_PATH_SCRIPT_DIR}/py_utils.sh"

# Bash-Tools globals
BSHT_FLAG_QUIET=${BSHT_FLAG_QUIET:-0}
BSHT_FLAG_LOG_FILE_ENABLED=${BSHT_FLAG_LOG_FILE_ENABLED:-1}
BSHT_PATH_LOG_FILE=${PYI_PATH_SCRIPT_DIR}/install.log

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

cleanup() {
  echo ""
  util_infotext "cleaning up before exit.."
  if [[ -e $GLB_PATH_TMP_DIR ]]; then
    rm -r "$GLB_PATH_TMP_DIR"
    util_infotext "  --> removed '$GLB_PATH_TMP_DIR'"
  fi
  if [[ -e $PYI_PATH_INSTALL_TARGET ]] && (( PYI_FLAG_DIR_CREATED )); then
    rm -r "$PYI_PATH_INSTALL_TARGET"
    util_infotext "  --> removed '$PYI_PATH_INSTALL_TARGET'"
  fi
  if [[ -e $PYI_PATH_SWAPFILE ]]; then
    swapoff "$PYI_PATH_SWAPFILE" > /dev/null 2>&1
    rm -f "$PYI_PATH_SWAPFILE"
    util_infotext "  --> disabled temporary swapfile and removed '$PYI_PATH_SWAPFILE'"
  fi
}

# ----- GLOBALS --------------------------------------

# Flags
PYI_FLAG_MKDIR=0
PYI_FLAG_DIR_CREATED=0
PYI_FLAG_REDUCED_PERF=0

# Vars
PYI_VAR_CORES=0
PYI_VAR_PY_VERSION=""

# URLs
PYI_URL_PY_SRC=""
PYI_URL_PY_SRC_BASE=""

# Paths
PYI_PATH_TARBALL=""
PYI_PATH_TMP_DIR=""
PYI_PATH_TMP_FILE=""
PYI_PATH_SWAPFILE=""
PYI_PATH_BUILD_DIR=""
PYI_PATH_BUILD_LOG=""
PYI_PATH_INSTALL_TARGET=""
PYI_PATH_INSTALL_PREFIX=""

# ----- ARGUMENTS ------------------------------------

while getopts d:u:v:fqh flag; do
  case "$flag" in
    d) PYI_PATH_INSTALL_TARGET=$OPTARG ;;
    u) PYI_URL_PY_SRC=$OPTARG ;;
    v) PYI_VAR_PY_VERSION=$OPTARG ;;
    f) PYI_FLAG_MKDIR=1 ;;
    q) BSHT_FLAG_QUIET=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

# ----- VALIDATION -----------------------------------

if [[ $EUID -ne 0 ]]; then
  (( BSHT_FLAG_QUIET )) || echo -e "\nmust be run as root, retrying with sudo\n"
  exec sudo "$0" "$@"
fi

if [[ -z $PYI_PATH_INSTALL_TARGET ]]; then
  util_exit_with_error "missing argument: -d [PATH]"
fi

if [[ -z $PYI_URL_PY_SRC && -z $PYI_VAR_PY_VERSION ]]; then
  util_exit_with_error "missing argument: specify one of -u [URL] or -v [VERSION]"
fi

if [[ -n $PYI_URL_PY_SRC && -n $PYI_VAR_PY_VERSION ]]; then
  util_exit_with_error "too many arguments: specify one of -u [URL] OR -v [VERSION], not both"
fi

if ! [[ -d $PYI_PATH_INSTALL_TARGET ]] && ! (( PYI_FLAG_MKDIR )); then
  util_exit_with_error "directory '$PYI_PATH_INSTALL_TARGET' does not exist, -f not set so will not create"
fi

# ----- SETUP ----------------------------------------

PYI_VAR_CORES=$(nproc)
PYI_PATH_SWAPFILE=/var/py_build_swap
PYI_PATH_TMP_DIR=$(mktemp -d) || util_exit_with_error "'mktemp' failed to create temporary directory in /tmp"
PYI_PATH_TMP_FILE=$(mktemp -u python.XXXXXX) || util_exit_with_error "'mktemp' failed to generate temporary filename"
PYI_PATH_BUILD_LOG=${PYI_PATH_SCRIPT_DIR}/py_build.log
PYI_PATH_TARBALL=${PYI_PATH_TMP_DIR}/${PYI_PATH_TMP_FILE}
PYI_URL_PY_SRC_BASE="https://www.python.org/ftp/python/<PY_VER>/Python-<PY_VER>.tgz"

trap cleanup EXIT

# ----- RUN ------------------------------------------

# ----- INSTALL DIRECTORY -------------

if ! [[ -d $PYI_PATH_INSTALL_TARGET ]] && (( PYI_FLAG_MKDIR )); then
  util_infotext "$PYI_PATH_INSTALL_TARGET does not exist, it will be created"
  mkdir -p "$PYI_PATH_INSTALL_TARGET"
  PYI_FLAG_DIR_CREATED=1
fi

# ----- DOWNLOAD/EXTRACT --------------

if [[ -z $PYI_URL_PY_SRC && -n $PYI_VAR_PY_VERSION ]]; then
  PYI_URL_PY_SRC=$(sed "s/<PY_VER>/${PYI_VAR_PY_VERSION}/g" <<< $PYI_URL_PY_SRC_BASE)
fi

util_infotext "this script will attempt to install Python from source"
util_infotext "download url: $PYI_URL_PY_SRC"
util_infotext "install path: $PYI_PATH_INSTALL_TARGET"
util_infotext "downloading archive, please wait.."

if ! util_download_file "$PYI_URL_PY_SRC" "$PYI_PATH_TARBALL"; then
  util_exit_with_error "download failed, please check the URL and try again"
fi

util_infotext "download complete" "extracting tarball.."
tar -xzf "$PYI_PATH_TARBALL" -C "$PYI_PATH_TMP_DIR"
util_infotext "extraction complete" "checking for conflicting versions in '$PYI_PATH_INSTALL_TARGET'.."

# ----- VERSION CONFLICTS -------------

if [[ -z $PYI_VAR_PY_VERSION ]]; then
  version_str=("$PYI_PATH_TMP_DIR"/*/)
  version_str=${version_str[0]%/}
  version_str=${version_str##*/}
  if ! PYI_VAR_PY_VERSION=$(py_util_parse_version_string "$version_str" | sed 's/ /./g'); then
    util_exit_with_error "unable to determine version number from downloaded Python tarball"
  fi
fi

if ! existing=$(py_util_detect_version_conflicts "$PYI_PATH_INSTALL_TARGET" "$PYI_VAR_PY_VERSION"); then
  echo "$existing"
  util_exit_with_error "unable to continue, change install path or remove existing version"
fi
util_infotext "no conflicts detected"

if py_util_version_lt "$PYI_VAR_PY_VERSION" "3.7.0"; then
  util_infotext "note: legacy versions are likely to fail during configuration/build"
  util_infotext "note: legacy versions will expect exec paths and environment setups that are no longer standard in linux"
  util_infotext "note: building is not impossible but will require manual setup before trying to build"
  if ! util_ask_confirm "do you want to continue and try to build?"; then
    util_infotext "cancelled"
    exit 0
  fi
fi

PYI_PATH_BUILD_DIR=("$PYI_PATH_TMP_DIR"/*/)
PYI_PATH_INSTALL_PREFIX=${PYI_PATH_INSTALL_TARGET}/python-${PYI_VAR_PY_VERSION%.*}

# ----- INSTALL BUILD TOOLS -----------

util_infotext "checking/installing build dependencies using apt.."
if ! py_util_install_build_dependencies; then
  util_exit_with_error "apt-get failed to install build dependencies"
fi
util_infotext "dependencies installed"

# ----- SYSTEM MEMORY/SWAP ------------

util_infotext "checking system memory setup" "a temporary swapfile may be created during this process, it will be removed automatically"
if retval=$(py_util_build_swap "$GLB_PATH_SWAPFILE"); then
  [[ $retval == "PERF_1" ]] && GLB_FLAG_REDUCED_PERF=1
  [[ $retval == "PERF_2" ]] && util_infotext "no temporary swapfile needed"
else
  util_warntext "a temporary swapfile was required due to the limited system memory available"
  util_exit_with_error "swapfile allocation failed" "cannot continue with current memory setup"
fi

# ----- CONFIGURE/BUILD ---------------

util_infotext "moving into build directory.." "  --> $PYI_PATH_BUILD_DIR"
cd "$PYI_PATH_BUILD_DIR"

util_infotext "configuring.." "  --enable-optimizations" "  --with-ensurepip=install" "  --prefix=$PYI_PATH_INSTALL_PREFIX"
if ! ./configure --enable-optimizations --with-ensurepip=install --prefix="$PYI_PATH_INSTALL_PREFIX" > "$PYI_PATH_BUILD_LOG" 2>&1; then
  util_infotext "'./configure' failed (exit code: $?)"
  if util_ask_confirm "would you like to see the full build log now?"; then
    (( BSHT_FLAG_QUIET )) || cat "$PYI_PATH_BUILD_LOG"
  fi
  exit 1
fi

util_infotext "configure complete" "note that building may take +1hr on limited hardware"
util_infotext "all build output is redirected into '$PYI_PATH_BUILD_LOG'" "building.."

(( PYI_FLAG_REDUCED_PERF )) && PYI_VAR_CORES=2

if ! make -j${PYI_VAR_CORES} > "$PYI_PATH_BUILD_LOG" 2>&1; then
  util_infotext "'make' failed (exit code: $?)"
  if util_ask_confirm "would you like to see the full build log now?"; then
    (( BSHT_FLAG_QUIET )) || cat "$PYI_PATH_BUILD_LOG"
  fi
  exit 1
fi

# ----- INSTALL -----------------------

util_infotext "build complete" "installing.."
if ! make altinstall > "$PYI_PATH_BUILD_LOG" 2>&1; then
  util_infotext "'make altinstall' failed (exit code: $?)"
  if util_ask_confirm "would you like to see the full build log now?"; then
    (( BSHT_FLAG_QUIET )) || cat "$PYI_PATH_BUILD_LOG"
  fi
  exit 1
fi

# dont do this?
#ln -s "${PYI_PATH_INSTALL_PREFIX}" "${PYI_PATH_INSTALL_PREFIX}/bin/python3"

# ----- EXIT --------------------------

util_infotext "install complete"
util_infotext "  --> installed to: $PYI_PATH_INSTALL_PREFIX" " --> binary: ${PYI_PATH_INSTALL_PREFIX}/bin/python${PYI_VAR_PY_VERSION%.*}"
util_infotext "this version has NOT been added to your path"
exit 0
