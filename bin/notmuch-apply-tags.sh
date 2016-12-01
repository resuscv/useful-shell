#!/bin/sh
#
# Script to take Maildir(-type) files from a notmuch search and
#   - extract the Gmail tags from X-Keywords
#   - flag if the message is "historical"
#   - add tags to the messages in the notmuch database
#
# INPUT is a messageID -- So use something like:
#   - No arguments means, do everything tagged 'new'
#       notmuch-apply-tags.sh
#   - Act on particular messages
#       notmuch-apply-tags.sh <msg-id> <msg-id> ...
#
# Find message IDs with a command like:  notmuch search --output=messages tag:new


SELF=$(basename $0)
# Run the apply after this many messages have been processed
BATCH_SIZE=1000

if [ $# -eq 0 ]; then
    MSGIDs=$(notmuch search --output=messages tag:new)
else
    MSGIDs="$@"
fi

fatal() {
    echo "$SELF: fatal: $1" >&2
        [ -z $2 ] && exit 1
        exit $2
}


batch_apply_tags() {
    # Now apply the tags
    if [ -s ${TMPFILE} ]; then
        echo "-----\nNow we just batch apply the tags...   There are $(wc -l < ${TMPFILE})"
        ${_E} notmuch tag --batch --input=${TMPFILE}
        ${_E} sleep 2
    else
        echo "-----\nNo new gmail-type messages or no tagging to be done"
    fi
    # and clean up after ourselves...
    cat /dev/null > ${TMPFILE}
}



TMPFILE=$(mktemp) || fatal "mktemp failed"


# Set `DEBUG` environment to NOT run the tagging, but to simply collect the tags
[[ -n ${DEBUG} ]] && _E=echo

# Where does my email live?
DB_PATH=$(notmuch config get database.path)
[[ -n ${DEBUG} ]] && echo "Email path is: ${DB_PATH}"


count=0
for m in ${MSGIDs}; do
    count=$(expr $count + 1)
    echo "Processing: $m   (${count} of at most ${BATCH_SIZE})"
    # Now find the filenames - there can be multiple files with the same MSGID
    notmuch search --output=files ${m} | \
        while read f; do
            [[ -n ${DEBUG} ]] && echo "... file is: $f"

            TAGS=""

            #####
            # Gmail messages
            # N.B. The following changes are made to tags:
            #      1. Remove back slashes '\'
            #      2. Spaces ' ' are replaced with underscores '_'
            #      3. Tags starting '-' (with any number of following
            #         spaces) have it removed
            #      4. Tags are made lower case (I can't be bothered
            #         hitting SHIFT)
            gmail_TAGS=$(sed '/^$/Q' "$f" | \
                grep '^X-Keywords: ' | \
                sed -e 's/^X-Keywords: /+/' \
                    -e 's/^\+$//' \
                    -e 's/\\//g' \
                    -e 's/ /_/g' \
                    -e 's/,/ +/g' \
                    -e 's/+-_*/+/g' \
                | \
                tr '[:upper:]' '[:lower:]')
            TAGS="${gmail_TAGS} ${TAGS}"

            #####
            # Check to see if the email is in the 'historical' directory
            # Old/retired mail accounts live in ${NOTMUCH_PATH}/historical
            echo $f | \
                grep -q "^${DB_PATH}/historical" \
                && TAGS="+historical ${TAGS}"

            #####
            # Now remove the 'new' tag from the message
            TAGS="-new ${TAGS}"

            #####
            # Handle the case of no tags from 'X-Keywords'
            # or no 'X-Keywords'
            echo "... tags: >>${TAGS}<<"

            if [ "${TAGS}" != "+" ] && [ ! -z "${TAGS}" ]; then
                echo "${TAGS} -- ${m}" >> ${TMPFILE}
            fi

        done
    if [ $count -ge ${BATCH_SIZE} ]; then
        count=0
        batch_apply_tags
    fi
done

# Apply what's left...
batch_apply_tags

${_E} rm -f ${TMPFILE}

echo "Done!"
#echo "\nDon't forget to remove 'new' tag."
