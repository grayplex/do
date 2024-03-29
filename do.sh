#!/bin/bash
#########################################################################
# Title:        DigitalOceanInit: DO Script                             #
# Author(s):    Ken Schultz                                             #
# URL:          https://github.com/grayplex/do                          #
# Description:  Script for initial DigitalOcean server setup            #
#               Tested on Ubuntu 22.04                                  #
#########################################################################
#                   GNU General Public License v3.0                     #
#########################################################################

################################
# Privilege Escalation
################################

# Restart script in SUDO
# https://unix.stackexchange.com/a/28793

if [ $EUID != 0 ]; then
    exec sudo -- "$0" "$@"
    exit $?
fi

################################
# Scripts
################################

source /srv/git/do/yaml.sh
create_variables /srv/git/grayplex/accounts.yml

################################
# Variables
################################

# Ansible
ANSIBLE_PLAYBOOK_BINARY_PATH="/usr/local/bin/ansible-playbook"

# Grayplex
GRAYPLEX_REPO_PATH="/srv/git/grayplex"
GRAYPLEX_PLAYBOOK_PATH="$GRAYPLEX_REPO_PATH/grayplex.yml"

# DO
DO_REPO_PATH="/srv/git/do"

readonly PYTHON_CMD_SUFFIX="-m pip install \
                            --timeout=360 \
                            --no-cache-dir \
                            --disable-pip-version-check \
                            --upgrade"
readonly PYTHON3_CMD="/srv/ansible/venv/bin/python3 $PYTHON_CMD_SUFFIX"

################################
# Functions
################################

git_fetch_and_reset () {
    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git checkout --quiet "${GRAYPLEX_BRANCH:-master}" >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git submodule update --init --recursive
    chmod 664 "${GRAYPLEX_REPO_PATH}/ansible.cfg"
    # shellcheck disable=SC2154
    chown -R "${user_name}":"${user_name}" "${GRAYPLEX_REPO_PATH}"
}

git_fetch_and_reset_do () {
    git fetch --quiet >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git checkout --quiet master >/dev/null
    git clean --quiet -df >/dev/null
    git reset --quiet --hard "@{u}" >/dev/null
    git submodule update --init --recursive
    chmod 775 "${DO_REPO_PATH}/do.sh"
}

run_playbook_do () {
    local arguments=$*

    cd "${GRAYPLEX_REPO_PATH}" || exit

    # shellcheck disable=SC2086
    "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${GRAYPLEX_PLAYBOOK_PATH}" \
        --become \
        ${arguments}

    local return_code=$?

    cd - >/dev/null || exit

    if [ $return_code -ne 0 ]; then
        echo "========================="
        echo ""
        if [ $return_code -eq 99 ]; then
        echo "Error: Playbook run was aborted by the user."
        echo ""
        else
        echo "Error: Playbook run failed, scroll up to the failed task to review."
        echo ""
        exit 1
        fi
        exit
    fi
}

install () {
    local arg=("$@")

    if [ -z "$arg" ]
    then
        echo -e "No install tag was provided.\n"
        usage
        exit 1
    fi

    # Remove space after comma
    # shellcheck disable=SC2128,SC2001
    local arg_clean
    arg_clean=${arg//, /,}

    # Split tags from extra arguments
    # https://stackoverflow.com/a/10520842
    local re="^(\S+)\s+(-.*)?$"
    if [[ "$arg_clean" =~ $re ]]; then
        local tags_arg="${BASH_REMATCH[1]}"
        local extra_arg="${BASH_REMATCH[2]}"
    else
        tags_arg="$arg_clean"
    fi

    # Save tags into 'tags' array
    # shellcheck disable=SC2206
    local tags_tmp=(${tags_arg//,/ })

    # Remove duplicate entries from array
    # https://stackoverflow.com/a/31736999
    local tags=()
    readarray -t tags < <(printf '%s\n' "${tags_tmp[@]}" | awk '!x[$0]++')

    # Build DO tag arrays
    local tags_do

    for i in "${!tags[@]}"
    do
        #if [[ ${tags[i]} == sandbox-* ]]; then
        #tags_sandbox="${tags_sandbox}${tags_sandbox:+,}${tags[i]##sandbox-}"
        #elif [[ ${tags[i]} == mod-* ]]; then
        #tags_Grayplexmod="${tags_Grayplexmod}${tags_Grayplexmod:+,}${tags[i]##mod-}"
        #else
        tags_do="${tags_do}${tags_do:+,}${tags[i]}"
        #fi
    done

    # Grayplex Ansible Playbook
    if [[ -n "$tags_do" ]]; then
        # Build arguments
        local arguments_do="--tags $tags_do"

        if [[ -n "$extra_arg" ]]; then
        arguments_do="${arguments_do} ${extra_arg}"
        fi

        # Run playbook
        echo ""
        echo "Running Grayplex Tags: ${tags_do//,/,  }"
        echo ""
        run_playbook_do "$arguments_do"
        echo ""
    fi

}

update () {
    deploy_ansible_venv

    if [[ -d "${GRAYPLEX_REPO_PATH}" ]]
    then
        echo -e "Updating Grayplex...\n"

        cd "${GRAYPLEX_REPO_PATH}" || exit

        git_fetch_and_reset

        bash /srv/git/grayplex/scripts/update.sh

        local returnValue=$?

        if [ $returnValue -ne 0 ]; then
        exit $returnValue
        fi

        cp /srv/ansible/venv/bin/ansible* /usr/local/bin/
        sed -i 's/\/usr\/bin\/python3/\/srv\/ansible\/venv\/bin\/python3/g' /srv/git/grayplex/ansible.cfg

        run_playbook_do "--tags settings" && echo -e '\n'

        echo -e "Update Completed."
    else
        echo -e "Grayplex folder not present."
    fi
}

do-update () {
    echo -e "Updating do...\n"

    cd "${DO_REPO_PATH}" || exit

    git_fetch_and_reset_do

    echo -e "Update Completed."
}

do-list ()  {
    if [[ -d "${GRAYPLEX_REPO_PATH}" ]]
    then
        echo -e "Grayplex tags:\n"

        cd "${GRAYPLEX_REPO_PATH}" || exit

        "${ANSIBLE_PLAYBOOK_BINARY_PATH}" \
        "${GRAYPLEX_PLAYBOOK_PATH}" \
        --become \
        --list-tags --skip-tags "always" 2>&1 | grep "TASK TAGS" | cut -d":" -f2 | sed 's/[][]//g' | cut -c2- | sed 's/, /\n/g' | column

        echo -e "\n"

        cd - >/dev/null || exit
    else
        echo -e "Grayplex folder not present.\n"
    fi
}

grayplex-branch () {
    deploy_ansible_venv

    if [[ -d "${GRAYPLEX_REPO_PATH}" ]]
    then
        echo -e "Changing Grayplex branch to $1...\n"

        cd "${GRAYPLEX_REPO_PATH}" || exit

        GRAYPLEX_BRANCH=$1

        git_fetch_and_reset

        bash /srv/git/grayplex/scripts/update.sh

        local returnValue=$?

        if [ $returnValue -ne 0 ]; then
        exit $returnValue
        fi

        cp /srv/ansible/venv/bin/ansible* /usr/local/bin/
        sed -i 's/\/usr\/bin\/python3/\/srv\/ansible\/venv\/bin\/python3/g' /srv/git/grayplex/ansible.cfg

        run_playbook_do "--tags settings" && echo -e '\n'

        echo "Branch change and update completed."
    else
        echo "Grayplex folder not present."
    fi
}

bench () {
    wget -qO- bench.sh | bash
}

deploy_ansible_venv () {
    if [[ ! -d "/srv/ansible" ]]
    then
        mkdir -p /srv/ansible
        cd /srv/ansible || exit
        release=$(lsb_release -cs)

        if [[ $release =~ (focal)$ ]]; then
        echo "Focal, deploying venv with Python3.10."
        add-apt-repository ppa:deadsnakes/ppa --yes
        apt install python3.10 python3.10-dev python3.10-distutils python3.10-venv -y
        add-apt-repository ppa:deadsnakes/ppa -r --yes
        rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list
        rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list.save
        python3.10 -m venv venv
        elif [[ $release =~ (jammy)$ ]]; then
        echo "Jammy, deploying venv with Python3."
        python3 -m venv venv
        else
        echo "Unsupported Distro, defaulting to Python3."
        python3 -m venv venv
        fi
    else
        /srv/ansible/venv/bin/python3 --version | grep -q '^Python 3\.10.'
        local python_version_valid=$?

        if [ $python_version_valid -eq 0 ]; then
        echo "Python venv is running with Python 3.10."
        else
        echo "Python venv is not running with Python 3.10. Recreating."
        recreate-venv
        fi
    fi

    ## Install pip3
    cd /tmp || exit
    curl -sLO https://bootstrap.pypa.io/get-pip.py
    python3 get-pip.py

    $PYTHON3_CMD \
        tld argon2_cffi ndg-httpsclient \
        dnspython lxml jmespath \
        passlib PyMySQL docker \
        pyOpenSSL requests netaddr \
        jinja2

    chown -R "${user_name}":"${user_name}" "/srv/ansible"
}

list () {
    do-list
}

update-ansible () {
    bash "/srv/git/grayplex/scripts/update.sh"
}

recreate-venv () {
    echo "Recreating the Ansible venv."

    # Check for supported Ubuntu Releases
    release=$(lsb_release -cs)

    rm -rf /srv/ansible

    if [[ $release =~ (focal)$ ]]; then
        sudo add-apt-repository ppa:deadsnakes/ppa --yes
        sudo apt install python3.10 python3.10-dev python3.10-distutils python3.10-venv -y
        sudo add-apt-repository ppa:deadsnakes/ppa -r --yes
        sudo rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list
        sudo rm -rf /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-focal.list.save
        python3.10 -m ensurepip

        mkdir -p /srv/ansible
        cd /srv/ansible || exit
        python3.10 -m venv venv
    elif [[ $release =~ (jammy)$ ]]; then
        mkdir -p /srv/ansible
        cd /srv/ansible || exit
        python3 -m venv venv
    fi

    bash /srv/git/Grayplex/scripts/update.sh

    local returnValue=$?

    if [ $returnValue -ne 0 ]; then
        exit $returnValue
    fi

    cp /srv/ansible/venv/bin/ansible* /usr/local/bin/
    echo "Done recreating the Ansible venv."

    ## Install pip3
    cd /tmp || exit
    curl -sLO https://bootstrap.pypa.io/get-pip.py
    python3 get-pip.py

    $PYTHON3_CMD \
        tld argon2_cffi ndg-httpsclient \
        dnspython lxml jmespath \
        passlib PyMySQL docker \
        pyOpenSSL requests netaddr \
        jinja2

    chown -R "${user_name}":"${user_name}" "/srv/ansible"
}

inventory () {
    local file_path="/srv/git/grayplex/inventories/host_vars/localhost.yml"
    local default_editor="nano"
    local approved_editors=("nano" "vim" "vi" "emacs" "gedit" "code")

    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        echo "Error: The inventory file 'localhost.yml' does not yet exist."
        return 1
    fi

    # Check if EDITOR is in the approved list
    local is_approved=0
    for editor in "${approved_editors[@]}"; do
        if [[ "${EDITOR}" == "$editor" ]]; then
        is_approved=1
        break
        fi
    done

    if [[ "$is_approved" -eq 0 ]]; then
        if [[ -z "${EDITOR}" ]]; then
        # Use default if EDITOR is not set
        $default_editor "$file_path"
        else
        # Prompt for confirmation if EDITOR is not in approved list
        echo "The EDITOR variable is set to an unrecognized value: $EDITOR"
        # shellcheck disable=SC2162
        read -p "Are you sure you want to use it to edit the file? (y/N) " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            ${EDITOR} "$file_path"
        else
            echo "Using default editor: $default_editor"
            $default_editor "$file_path"
        fi
        fi
    else
        ${EDITOR:-$default_editor} "$file_path"
    fi
}

usage () {
    echo "Usage:"
    echo "    do update                     Updates Grayplex (resets the branch to master)."
    echo "    do list                       List Grayplex tags."
    echo "    do install <tag>              Install <tag>."
    echo "    do bench                      Run bench.sh"
    echo "    do recreate-venv              Re-create Ansible venv."
    echo "    do inventory                  Opens the 'localhost.yml' inventory file."
    echo "    do branch <branch>            Changes and updates the Grayplex branch."
    echo "    do sandbox-branch <branch>    Changes and updates the Sandbox branch."
}

################################
# Update Check
################################

cd "${DO_REPO_PATH}" || exit

git fetch
HEADHASH=$(git rev-parse HEAD)
UPSTREAMHASH=$(git rev-parse "master@{upstream}")

if [ "$HEADHASH" != "$UPSTREAMHASH" ]
then
    echo "Not up to date with origin. Updating."
    do-update
    echo "Relaunching with previous arguments."
    sudo "$0" "$@"
    exit 0
fi

################################
# Argument Parser
################################

# https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/

roles=""  # Default to empty role

# Parse options
while getopts ":h" opt; do
    case ${opt} in
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
shift $((OPTIND -1))

# Parse commands
subcommand=$1; shift  # Remove 'do' from the argument list
case "$subcommand" in

# Parse options to the various sub commands
    list)
        list
        ;;
    update)
        update
        ;;
    install)
        roles=${*}
        install "${roles}"
        ;;
    branch)
        grayplex-branch "${*}"
        ;;
    recreate-venv)
        recreate-venv
        ;;
    bench)
        bench
        ;;
    inventory)
        inventory
        ;;
    "") echo "A command is required."
        echo ""
        usage
        exit 1
        ;;
    *)
        echo "Invalid Command: $subcommand"
        echo ""
        usage
        exit 1
        ;;
esac
