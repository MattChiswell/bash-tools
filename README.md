# Readme

## Bash Tools

### Description
This repository contains a collection of bash tools that I maintain for various tasks on a range of different linux machines. Some tools have a specific use-case 
whilst others are more generic and could be imported into any existing script or project.
For the most part, they have been organised into folders that describe their purpose, tools that fit more than one category are most likely to be found in the 
`utils` folder along with the general-purpose scripts.
Most scripts will have their own help text that is accessible by passing the `-h` option at the command line, this will explain the options/commands/arguments for that specific script directly.

### Structure
Tools can be handpicked from these folders and imported into projects as-is or the entire repository can be cloned into a folder and referenced from there. In that case, the scripts in the repository may reference eachother and will only work like that if they remain within the repository. If the structure is changed or individual scripts are moved elsewhere, note that internal references/includes may need to be updated/removed.

### Tools
- Python
  - `install_from_source.sh` - Installs Python from source tarball; see `-h` for details on options;

### Requirements
- Bash >= 4.3
- curl or wget

### Tested on
- Debian 11+
- Ubuntu 20.04+

### License
This repository is released under GNU General Public License v3.0. The license can be found, in its entirety, within LICENSE at the root of the repository.
