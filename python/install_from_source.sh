#!/usr/bin/env bash

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

# ----- GLOBALS --------------------------------------

# Flags
GLB_FLAG_MKDIR=0

# Paths
GLB_INSTALL_PATH=""
GLB_TEMP_DL_FILE=""
GLB_TEMP_DL_PATH=""
GLB_TEMP_TARBALL=""
GLB_PYTHON_SRC_URL=""

# Regex
GLB_REGEX_PY_BIN="^python3\.[0-9]+(\.[0-9]+)?$"
GLB_REGEX_PY_TARBALL="^Python-3\.[0-9]+(\.[0-9]+)?$"

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

trap "rm -rf '$GLB_TEMP_DL_PATH'" EXIT
if ! download_file $GLB_PYTHON_SRC_URL $GLB_TEMP_TARBALL; then
  exit_with_error "download failed, please check the URL and try again"
fi

infotext "download complete" "extracting tarball.."

#mkdir -p "${GLB_TEMP_DL_PATH}/extract"
#tar -xzf "$GLB_TEMP_TARBALL" --strip-components=1 -C "${GLB_TEMP_DL_PATH}/extract"
tar -xzf "$GLB_TEMP_TARBALL" -C "$GLB_TEMP_DL_PATH"
extracted=$(ls "$GLB_TEMP_DL_PATH" | grep -oE "$GLB_REGEX_PY_TARBALL" | sed "s/Python-//")
detected=$(ls "$GLB_INSTALL_PATH" | grep -oE "$GLB_REGEX_PY_BIN" | sed "s/python//")

infotext "extraction complete" "checking for conflicting versions in '$GLB_INSTALL_PATH'.."

if match=$(grep -Fx "${extracted%.*}" <<< "$detected"); then
  infotext "version conflict detected" "python${match} was detected in '$GLB_INSTALL_PATH'" "you are trying to install python${extracted}"
  exit_with_error "cannot install matching major version in this directory" "remove existing version or change install path and try again"
fi

infotext "configuring.." "  --enable-optimizations" "  --with-ensurepip=install" "  --prefix=$GLB_INSTALL_PATH"
