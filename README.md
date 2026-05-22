# Readme

## Bash Tools

### Description
This repository contains a collection of bash tools that I maintain for various tasks on a range of different linux machines. Some tools have a specific use-case 
whilst others are more generic and could be imported into any existing script or project.
They have been organised as a library of related tools and should, for the most part, be imported via the entry script `bashtools.lib.sh` if you plan on using them together in a project. This entry script will import all libraries from the `lib` directory, all of their functions will be available in your scripts immediately. All of the library functions are namespaced to facilitate ease-of-use.

### Structure
- `lib`
  - Tools can be handpicked from these folders and imported into projects as-is or the entire repository can be cloned into a folder and referenced from there. In that case, the scripts in the repository may reference eachother and will only work like that if they remain within the repository. If the structure is changed or individual scripts are moved elsewhere, note that internal references/includes may need to be updated/removed. Again, the simplest import method is to source the library entry script into your project.
- `bin`
  - These are command line tools with options/arguments for several different tasks. They depend on various functions from the library itself. These are designed to be run at the command line, not sourced into other files. The tools all have a help text that is available with the `-h` flag. If you make use of these tools, again, the simplest method would be to clone the repository, leave the structure unchanged and simply add this `bin` directory to your path, allowing for very easy system-wide usage.

### Globals
There are several global variables that are used by various parts of the library, these can be set inside your project or at the command line. They all have default values which are set in `bashtools.lib.sh`. Globals that can be modified are:
- `BSHT_PATH_LOG_FILE`
- `BSHT_FLAG_QUIET`
- `BSHT_FLAG_DEBUG`
- `BSHT_FLAG_NO_ROOT`
- `BSHT_FLAG_LOG_SIMPLE`
- `BSHT_FLAG_LOG_FILE_ENABLED`

### Binaries
- `bin/py_install.sh` - installs Python from source; accepts URL to tarball or just a version number for automatic download; extensive help dialog accessible with `-h`

### Tools
- `lib/core/error.sh` - error handling and capture
- `lib/core/logging.sh` - terminal and file based logging
- `lib/general/utils.sh` - general purpose utility functions (memory, disk space, arrays etc)
- `lib/python/utils.sh` - functions related to python management/interaction (building, venv, module testing etc)
- `lib/os/dietpi/utils.sh` - functions targetting DietPi OS specifically

### Usage
To make use of the library functions, the simplest method is to clone the repository and source the entry script into your project, for example:
```bash
source "/full/path/to/bashtools.lib.sh"
```
If you wish to make use of the included binaries/scripts, if you would prefer not to type the full file path everytime you wish to call one, you can add the `bin` folder to your path, for example:
```bash
export PATH=$PATH:/full/path/to/bin
```

### Requirements
- Bash >= 4.3
- curl or wget

### Tested on
- Debian 11+
- DietPi 9+
- Ubuntu 20.04+

### License
This repository is released under GNU General Public License v3.0. The license can be found, in its entirety, within LICENSE at the root of the repository.

### Source
https://github.com/MattChiswell/bash-tools
