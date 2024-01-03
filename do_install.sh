#!/bin/bash
#shellcheck disable=SC2220
#########################################################################
# Title:        DigitalOcean Install Script                             #
# Author(s):    Ken Schultz                                             #
# URL:          https://github.com/grayplex/do            #
# Description:  Script for initial DigitalOcean server setup            #
#               Tested on Ubuntu 22.04                                  #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Variables                    
################################

VERBOSE=false
VERBOSE_OPT=""
DO_REPO="https://github.com/grayplex/do.git"
DO_PATH="/srv/git/do"
DO_INSTALL_SCRIPT="$DO_PATH/do_install.sh"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
BRANCH="master"

################################
# Functions
################################

run_cmd() {
    local cmd_exit_code

    if $VERBOSE; then
        printf '%s\n' "+ $*" >&2;
        "$@"
        cmd_exit_code=$?
    else
        "$@" >/dev/null 2>&1
        cmd_exit_code=$?
    fi

    if [ $cmd_exit_code -ne 0 ]; then
        echo "Command failed with exit code $cmd_exit_code: $*" >&2
        exit $cmd_exit_code
    fi
}

################################
# Argument Parser
################################

while getopts 'vb:' f; do
    case $f in
    v)  VERBOSE=true
        VERBOSE_OPT="-v"
    ;;
    b)  BRANCH="$OPTARG"
    ;;
    esac
done

################################
# Main
################################

# Check for supported Ubuntu Releases
release=$(lsb_release -cs)

# Add more releases like (focal|jammy)$
if [[ $release =~ (focal|jammy)$ ]]; then
    echo "$release is currently supported."
elif [[ $release =~ (placeholder)$ ]]; then
    echo "$release is currently in testing."
else
    echo "==== UNSUPPORTED OS ===="
    echo "Install cancelled: $release is not supported."
    echo "Supported OS: 20.04 (focal) and 22.04 (jammy)"
    echo "==== UNSUPPORTED OS ===="
    exit 1
fi

# Check if using valid arch
arch=$(uname -m)

if [[ $arch =~ (x86_64)$ ]]; then
    echo "$arch is currently supported."
else
    echo "==== UNSUPPORTED CPU Architecture ===="
    echo "Install cancelled: $arch is not supported."
    echo "Supported CPU Architecture(s): x86_64"
    echo "==== UNSUPPORTED CPU Architecture ===="
    exit 1
fi

# Check for LXC using systemd-detect-virt
if systemd-detect-virt -c | grep -qi 'lxc'; then
    echo "==== UNSUPPORTED VIRTUALIZATION ===="
    echo "Install cancelled: Running in an LXC container is not supported."
    echo "==== UNSUPPORTED VIRTUALIZATION ===="
    exit 1
fi

echo "Installing Grayplex DigitalOcean Dependencies."

$VERBOSE && echo "Script Path: $SCRIPT_PATH"

# Update apt cache
run_cmd apt-get update

# Install git
run_cmd apt-get install -y git

# Remove existing repo folder
if [ -d "$DO_PATH" ]; then
    run_cmd rm -rf $DO_PATH;
fi

# Clone DO repo
run_cmd mkdir -p /srv/git
run_cmd mkdir -p /srv/ansible
run_cmd git clone --branch master "${DO_REPO}" "$DO_PATH"

# Set chmod +x on script files
run_cmd chmod +x $DO_PATH/*.sh

$VERBOSE && echo "Script Path: $SCRIPT_PATH"
$VERBOSE && echo "SB Install Path: "$DO_INSTALL_SCRIPT

## Create script symlinks in /usr/local/bin
shopt -s nullglob
for i in "$DO_PATH"/*.sh; do
    if [ ! -f "/usr/local/bin/$(basename "${i%.*}")" ]; then
        run_cmd ln -s "${i}" "/usr/local/bin/$(basename "${i%.*}")"
    fi
done
shopt -u nullglob

# Install DigitalOceanInit Dependencies
run_cmd bash -H $DO_PATH/do_dep.sh $VERBOSE_OPT

# Clone DigitalOcean repo
run_cmd bash -H $DO_PATH/do_repo.sh -b "${BRANCH}" $VERBOSE_OPT
