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
PYI_PATH_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd -P)

# load required scripts
source "${PYI_PATH_SCRIPT_DIR}/../bashtools.lib.sh"

# Bash-Tools globals
BSHT_FLAG_QUIET=0
BSHT_FLAG_LOG_FILE_ENABLED=0
BSHT_PATH_LOG_FILE=${PYI_PATH_SCRIPT_DIR}/install.log

# ----- HELPERS --------------------------------------

usage() {
  printf "\nusage: $0 [OPTIONS]\n"
  printf "  options:\n"
  printf "    -d    install directory / prefix (/opt is recommended)\n"
  printf "    -u    python source file url (expects .tgz archive)\n"
  printf "    -v    python version number to download and install\n"
  printf "    -f    if install path does not exist, create it\n"
  printf "    -q    quite mode, dont output anything to terminal (except errors) and assume 'yes' for any prompts\n"
  printf "    -h    display this help text\n"
  printf "  info:\n"
  printf "    -d    always required\n"
  printf "    -u -v specifiy one, not both\n"
  printf "    -v    supports versions >= 2.0.1; ensure you use the exact version as specified on the official download server\n"
  printf "  versions:\n"
  printf "    >= 3.8           latest should have no issues building\n"
  printf "    >= 3.5, <= 3.7   may have some minor issues but will likely build\n"
  printf "    >= 3.3, <= 3.4   will require tweaking for a successful build\n"
  printf "    >= 3.0, <= 3.2   are often broken and will not build without patching\n"
  printf "    2.7              will often build but can be messy\n"
  printf "    <= 2.6           will require extensive patching\n"
  printf "    this script is intended to configure and build only\n"
  printf "    if you are trying to install a legacy version, no prior setup/patching will be done here, you must do this yourself\n\n"
  exit 1
}

function build_swap() {
  local swapfile=$1
  local total_mem=$(general::check_memory) || return 1
  if [[ $total_mem -lt 1048576 ]]; then
    # 3G swap
    printf "PERF_1"
    if ! general::create_swap 3145728 "$swapfile"; then
      return 1
    fi
  elif [[ $total_mem -gt 1048576 && $total_mem -lt 2097152 ]]; then
    # 2G swap
    printf "PERF_1"
    if ! general::create_swap 2097152 "$swapfile"; then
      return 1
    fi
  elif [[ $total_mem -gt 2097152 && $total_mem -lt 3145728 ]]; then
    # 1G swap
    if ! general::create_swap 1048576 "$swapfile"; then
      return 1
    fi
  elif [[ $total_mem -gt 3145728 ]]; then
    # no extra swap needed
    printf "PERF_2"
    return 0
  else
    # failure somewhere
    return 1
  fi
}

function cleanup() {
  (( PYI_VAR_CLEANUP_HAS_RUN )) && return
  printf "\n"
  log::info "cleaning up before exit.."
  if [[ -e $PYI_PATH_TMP_DIR ]]; then
    rm -r "$PYI_PATH_TMP_DIR"
    log::info "  --> removed '$PYI_PATH_TMP_DIR'"
  fi
  if [[ -e $PYI_PATH_INSTALL_TARGET ]] && (( PYI_FLAG_DIR_CREATED )); then
    rm -r "$PYI_PATH_INSTALL_TARGET"
    log::info "  --> removed '$PYI_PATH_INSTALL_TARGET'"
  fi
  if [[ -e $PYI_PATH_SWAPFILE ]]; then
    swapoff "$PYI_PATH_SWAPFILE" > /dev/null 2>&1
    rm -f "$PYI_PATH_SWAPFILE"
    log::info "  --> disabled temporary swapfile and removed '$PYI_PATH_SWAPFILE'"
  fi
  PYI_VAR_CLEANUP_HAS_RUN=1
}

# ----- GLOBALS --------------------------------------

# Flags
PYI_FLAG_MKDIR=0
PYI_FLAG_DIR_CREATED=0
PYI_FLAG_REDUCED_PERF=0

# Vars
PYI_VAR_CORES=0
PYI_VAR_PY_VERSION=""
PYI_VAR_CLEANUP_HAS_RUN=0

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
    q) BSHT_FLAG_QUIET=1 && BSHT_FLAG_LOG_FILE_ENABLED=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

# ----- VALIDATION -----------------------------------

if [[ $EUID -ne 0 ]]; then
  (( BSHT_FLAG_QUIET )) || printf "\nmust be run as root, retrying with sudo\n"
  exec sudo "$0" "$@"
fi

if [[ -z $PYI_PATH_INSTALL_TARGET ]]; then
  error::die "missing argument: -d [PATH]"
fi

if [[ -z $PYI_URL_PY_SRC && -z $PYI_VAR_PY_VERSION ]]; then
  error::die "missing argument: specify one of -u [URL] or -v [VERSION]"
fi

if [[ -n $PYI_URL_PY_SRC && -n $PYI_VAR_PY_VERSION ]]; then
  error::die "too many arguments: specify one of -u [URL] OR -v [VERSION], not both"
fi

if ! [[ -d $PYI_PATH_INSTALL_TARGET ]] && ! (( PYI_FLAG_MKDIR )); then
  error::die "directory '$PYI_PATH_INSTALL_TARGET' does not exist, -f not set so will not create"
fi

# ----- SETUP ----------------------------------------

PYI_VAR_CORES=$(nproc)
PYI_PATH_SWAPFILE=/var/py_build_swap
PYI_PATH_TMP_DIR=$(mktemp -d) || error::die "'mktemp' failed to create temporary directory in /tmp"
PYI_PATH_TMP_FILE=$(mktemp -u python.XXXXXX) || error::die "'mktemp' failed to generate temporary filename"
PYI_PATH_BUILD_LOG=${PYI_PATH_SCRIPT_DIR}/py_build.log
PYI_PATH_TARBALL=${PYI_PATH_TMP_DIR}/${PYI_PATH_TMP_FILE}
PYI_URL_PY_SRC_BASE="https://www.python.org/ftp/python/<PY_VER>/Python-<PY_VER>.tgz"

trap cleanup "${BSHT_VAR_TRAP_SIGNALS[@]}"

# ----- RUN ------------------------------------------

# ----- INSTALL DIRECTORY -------------

if ! [[ -d $PYI_PATH_INSTALL_TARGET ]] && (( PYI_FLAG_MKDIR )); then
  log::info "$PYI_PATH_INSTALL_TARGET does not exist, it will be created"
  mkdir -p "$PYI_PATH_INSTALL_TARGET"
  PYI_FLAG_DIR_CREATED=1
fi

# ----- DOWNLOAD/EXTRACT --------------

if [[ -z $PYI_URL_PY_SRC && -n $PYI_VAR_PY_VERSION ]]; then
  PYI_URL_PY_SRC=$(sed "s/<PY_VER>/${PYI_VAR_PY_VERSION}/g" <<< $PYI_URL_PY_SRC_BASE)
fi

log::info "this script will attempt to install Python from source"
log::info "download url: $PYI_URL_PY_SRC"
log::info "install path: $PYI_PATH_INSTALL_TARGET"
log::info "downloading archive, please wait.."

if ! general::download_file "$PYI_URL_PY_SRC" "$PYI_PATH_TARBALL"; then
  error::die "download failed, please check the URL and try again"
fi

log::info "download complete" "extracting tarball.."
error::try tar -xzf "$PYI_PATH_TARBALL" -C "$PYI_PATH_TMP_DIR" || {
  error::die "unable to continue"
}
log::info "extraction complete" "checking for conflicting versions in '$PYI_PATH_INSTALL_TARGET'.."

# ----- VERSION CONFLICTS -------------

if [[ -z $PYI_VAR_PY_VERSION ]]; then
  version_str=("$PYI_PATH_TMP_DIR"/*/)
  version_str=${version_str[0]%/}
  version_str=${version_str##*/}
  if ! PYI_VAR_PY_VERSION=$(python::parse_version_string "$version_str" | sed 's/ /./g'); then
    error::die "unable to determine version number from downloaded Python tarball"
  fi
fi

if ! existing=$(python::detect_conflicts "$PYI_PATH_INSTALL_TARGET" "$PYI_VAR_PY_VERSION"); then
  log::error "conflicting version detected: ${existing%.*}"
  error::die "unable to continue, change install path or remove existing version"
fi
log::info "no conflicts detected"

if python::version_lt "$PYI_VAR_PY_VERSION" "3.7.0"; then
  log::info "note: legacy versions are likely to fail during configuration/build"
  log::info "note: legacy versions will expect exec paths and environment setups that are no longer standard in linux"
  log::info "note: building is not impossible but will require manual setup before trying to build"
  if ! general::ask_confirm "do you want to continue and try to build?"; then
    log::info "cancelled"
    exit 0
  fi
fi

PYI_PATH_BUILD_DIR=("$PYI_PATH_TMP_DIR"/*/)
PYI_PATH_INSTALL_PREFIX=${PYI_PATH_INSTALL_TARGET}/python-${PYI_VAR_PY_VERSION%.*}

# ----- INSTALL BUILD TOOLS -----------

log::info "checking/installing build dependencies using apt.."
if ! python::install_build_dependencies; then
  error::die "apt-get failed to install build dependencies"
fi
log::info "dependencies installed"

# ----- SYSTEM MEMORY/SWAP ------------

log::info "checking system memory setup" "a temporary swapfile may be created during this process, it will be removed automatically"
if retval=$(build_swap "$PYI_PATH_SWAPFILE"); then
  [[ $retval == "PERF_1" ]] && PYI_FLAG_REDUCED_PERF=1
  [[ $retval == "PERF_2" ]] && log::info "no temporary swapfile needed"
else
  log::warn "a temporary swapfile was required due to the limited system memory available"
  error::die "swapfile allocation failed" "cannot continue with current memory setup"
fi

# ----- CONFIGURE/BUILD ---------------

log::info "moving into build directory.." "  --> $PYI_PATH_BUILD_DIR"
cd "$PYI_PATH_BUILD_DIR"

log::info "configuring.." "  --enable-optimizations" "  --with-ensurepip=install" "  --prefix=$PYI_PATH_INSTALL_PREFIX"
if ! ./configure --enable-optimizations --with-ensurepip=install --prefix="$PYI_PATH_INSTALL_PREFIX" > "$PYI_PATH_BUILD_LOG" 2>&1; then
  log::info "'./configure' failed (exit code: $?)"
  if general::ask_confirm "would you like to see the full build log now?"; then
    (( BSHT_FLAG_QUIET )) || cat "$PYI_PATH_BUILD_LOG"
  fi
  exit 1
fi

log::info "configure complete" "note that building may take +1hr on limited hardware"
log::info "all build output is redirected into '$PYI_PATH_BUILD_LOG'" "building.."

(( PYI_FLAG_REDUCED_PERF )) && PYI_VAR_CORES=2

if ! make -s -j${PYI_VAR_CORES} > "$PYI_PATH_BUILD_LOG" 2>&1; then
  log::info "'make' failed (exit code: $?)"
  if general::ask_confirm "would you like to see the full build log now?"; then
    (( BSHT_FLAG_QUIET )) || cat "$PYI_PATH_BUILD_LOG"
  fi
  exit 1
fi

# ----- INSTALL -----------------------

log::info "build complete" "installing.."
if ! make altinstall > "$PYI_PATH_BUILD_LOG" 2>&1; then
  log::info "'make altinstall' failed (exit code: $?)"
  if general::ask_confirm "would you like to see the full build log now?"; then
    (( BSHT_FLAG_QUIET )) || cat "$PYI_PATH_BUILD_LOG"
  fi
  exit 1
fi

# ----- EXIT --------------------------

log::info "install complete"
log::info "  --> installed to: $PYI_PATH_INSTALL_PREFIX" "  --> binary: ${PYI_PATH_INSTALL_PREFIX}/bin/python${PYI_VAR_PY_VERSION%.*}"
log::info "this version has NOT been added to your path"
exit 0
