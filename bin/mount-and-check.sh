#!/bin/sh
# Very braindead script to mount a drive (like a NAS)
#   AND
# check that a certain path exists
#
# Why?  Mounting is REALLY insecure.  So doing a blind mount with a `grep` check that a path exists gives some level of security.

# My toolkit of useful functions
. ~/bin/toolkit.sh

get_host() {
    local fullpath=$1
    local retval

    echo "${fullpath}" | sed -e 's=^.*//==' -e 's=/.*$=='
}


mount_drive() {
    local type=$1; shift
    local source=$1; shift
    local destination=$1; shift
    local other_args=$@
    # I'd use '-v' always and '-d' for debugging

    local hostname=$(get_host ${source})

    ${_E} traceroute -n ${hostname} \
        || fatal $? "traceroute failed"

    ${_E} mkdir -p ${destination} \
        || fatal $? "mkdir failed"

    ${_E} mount \
        ${other_args} \
        -t ${type} \
        ${source} \
        ${destination} \
        || fatal $? "Mount failed"
}


check_path() {
    local mount_path=${1}; shift
    local remote_path=$1; shift
    local remote_search=$1; shift
    local other_ls_args=$@

    ls ${other_ls_args} ${mount_path}/${remote_path} \
        | grep -q -- "${remote_search}" \
        || fatal $? "Check path failed"
}


mount_and_check() {
    local type=$1; shift
    local source=$1; shift
    local destination=$1; shift
    local remote_path=$1; shift
    local remote_search=$1; shift

    mount_drive \
        "${type}" \
        "${source}" \
        "${destination}" \
        -v

    check_path \
        "${destination}" \
        "${remote_path}" \
        "${remote_search}"
}



example_code() {
    echo "Here"

    mount_and_check \
        afp \
        'afp://mynas.local/pictures' \
        ~/mymount-point \
        2016 \
        Berlin

    echo "... $?"
    echo "Done"
}
