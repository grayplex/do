#!/bin/bash
#########################################################################
# Title:        DigitalOcean Repo Cloner Script                         #
# Author(s):    Ken Schultz                                             #
# URL:          https://github.com/grayplex/do                          #
# Description:  Script for initial DigitalOcean server setup            #
#               Tested on Ubuntu 22.04                                  #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Variables
################################

VERBOSE=false
BRANCH='master'
GRAYPLEX_PATH="/srv/git/grayplex"
GRAYPLEX_REPO="https://github.com/grayplex/digitaloceaninit.git"

################################
# Functions
################################

usage () {
    echo "Usage:"
    echo "    do_repo -b <branch>    Repo branch to use. Default is 'master'."
    echo "    do_repo -v             Enable Verbose Mode."
    echo "    do_repo -h             Display this help message."
}

################################
# Argument Parser
################################

while getopts ':b:vh' f; do
    case $f in
    b)  BRANCH=$OPTARG;;
    v)  VERBOSE=true;;
    h)
        usage
        exit 0
        ;;
    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        echo ""
        usage
        exit 1
        ;;
    esac
done

################################
# Functions
################################

run_cmd() {
    if $VERBOSE; then
        "$@"
    else
        "$@" &>/dev/null
    fi
}

################################
# Main
################################

$VERBOSE && echo "git branch selected: $BRANCH"

## Clone the repo and pull latest commit
if [ -d "$GRAYPLEX_PATH" ]; then
    if [ -d "$GRAYPLEX_PATH/.git" ]; then
        cd "$GRAYPLEX_PATH" || exit
        run_cmd git fetch --all --prune
        # shellcheck disable=SC2086
        run_cmd git checkout -f $BRANCH
        # shellcheck disable=SC2086
        run_cmd git reset --hard origin/$BRANCH
        run_cmd git submodule update --init --recursive
        $VERBOSE && echo "git branch: $(git rev-parse --abbrev-ref HEAD)"
    else
        cd "$GRAYPLEX_PATH" || exit
        run_cmd rm -rf library/
        run_cmd git init
        run_cmd git remote add origin "$GRAYPLEX_REPO"
        run_cmd git fetch --all --prune
        # shellcheck disable=SC2086
        run_cmd git branch $BRANCH origin/$BRANCH
        # shellcheck disable=SC2086
        run_cmd git reset --hard origin/$BRANCH
        run_cmd git submodule update --init --recursive
        $VERBOSE && echo "git branch: $(git rev-parse --abbrev-ref HEAD)"
    fi
else
    # shellcheck disable=SC2086
    run_cmd git clone -b $BRANCH "$GRAYPLEX_REPO" "$GRAYPLEX_PATH"
    cd "$GRAYPLEX_PATH" || exit
    run_cmd git submodule update --init --recursive
    $VERBOSE && echo "git branch: $(git rev-parse --abbrev-ref HEAD)"
fi

## Copy settings and config files into Grayplex folder
shopt -s nullglob
for i in "$GRAYPLEX_PATH"/defaults/*.default; do
    if [ ! -f "$GRAYPLEX_PATH/$(basename "${i%.*}")" ]; then
        run_cmd cp -n "${i}" "$GRAYPLEX_PATH/$(basename "${i%.*}")"
    fi
done
shopt -u nullglob

## Activate Git Hooks
cd "$GRAYPLEX_PATH" || exit
run_cmd bash "$GRAYPLEX_PATH"/bin/git/init-hooks
