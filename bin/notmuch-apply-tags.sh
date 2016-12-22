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
LAST_RUN=${XDG_CONFIG_HOME:=$HOME/.config}/${SELF}.lastrun

# Run the apply after this many messages have been processed
BATCH_SIZE=1000


fatal() {
    echo "$SELF: fatal: $1" >&2
        [ -z $2 ] && exit 1
        exit $2
}


batch_apply_tags() {
    # Now apply the tags
    if [ -s ${TMPFILE} ]; then
        echo "-----\nNow we just batch apply the tags...   There are $(wc -l < ${TMPFILE})"
        ${_E} notmuch tag --remove-all --batch --input=${TMPFILE} || exit 1
        ${_E} sleep 2
    else
        echo "-----\nNo new gmail-type messages or no tagging to be done"
    fi

    # and clean up after ourselves...
    cat /dev/null > ${TMPFILE}
}


make_reserved_wordlist() {
    echo "
attachment
draft
encrypted
flagged
important
new
passed
replied
signed
unread
" | sed 's/^/+/' | sed 's/$/ /' > ${1}
}


TMPFILE=$(mktemp) || fatal "mktemp failed"

# Track the last time we were run
touch ${TMPFILE}.lastrun

make_reserved_wordlist ${TMPFILE}.reserved

# Set `DEBUG` environment to NOT run the tagging, but to simply collect the tags
[[ -n ${DEBUG} ]] && _E=echo
echo "Temporary files are:  ${TMPFILE}"

# Where does my email live?
DB_PATH=$(notmuch config get database.path)
[[ -n ${DEBUG} ]] && echo "Email path is: ${DB_PATH}"


if [ $# -eq 0 ]; then
    MSGIDs=$(notmuch search --output=messages tag:new)
    # We also want to run on any files that have changed
    if [ -f ${LAST_RUN} ]; then
	echo "Searching for recently changed messages..."
	# We're run this before, so now find files that have changed since last time
	## Step 1: What directories do we want to NOT search?
	PRUNE=""
	for d in $(echo ".notmuch $(notmuch config get new.ignore)"); do
	    PRUNE="${PRUNE} -path ${DB_PATH}/${d} -prune -o"
	done
	## Step 2: Get all the Message-IDs
	changed_MSGIDs=$( \
	    find ${DB_PATH} $(echo ${PRUNE}) -type f -newer ${LAST_RUN} -print0 | \
		xargs -0 grep '^Message-ID: <' | \
		awk -F"[<>]" '/Message-ID/ {print $2}' | \
		sed 's/^/id:/' \
		      )
	[[ -n ${DEBUG} ]] && cat <<EOF
----  Start:RECENTLY CHANGED
${changed_MSGIDs}
----  End:RECENTLY CHANGED
EOF
	## Step 3: Get a unique list (odds on a "tag:new" message is also recently modified!
	MSGIDs=$(echo "${MSGIDs} ${changed_MSGIDs}" | \
			xargs -n1 | \
			sort -u)
    else
	echo "You've not run ${SELF} before.  Checking everything..."
	echo "I would expect to see this file:  ${LAST_RUN}"
	# Check everything...
	MSGIDs=$(notmuch search --output=messages '*')
    fi
else
    MSGIDs="$@"
fi


cat > ${TMPFILE}.all_msgids <<EOF
----  Start:ALL MESSAGE-IDs
${MSGIDs}
----  End:ALL MESSAGE-IDs
EOF

NUM_BATCHES=$(echo "1 + $(wc -l < ${TMPFILE}.all_msgids) / ${BATCH_SIZE}" | bc)

count=0
count_batch=1

for m in ${MSGIDs}; do
    count=$(expr $count + 1)
    if [ ${count} -eq 1 ]; then
	echo "Batch  ${count_batch}  of  ${NUM_BATCHES}"
	[[ -n ${DEBUG} ]] || echo "Expecting  ~$(echo "1 + ${BATCH_SIZE} / $(stty size | awk '{print $2}')" | bc)  rows of dots..."
    fi
    [[ -n ${DEBUG} ]] && echo "Processing: $m   (${count} of at most ${BATCH_SIZE})"
    [[ -n ${DEBUG} ]] || printf "."

    # Currently used and reserved tags...
    reserved_TAGS=$(notmuch dump ${m} | \
			   grep -of ${TMPFILE}.reserved | \
			   xargs )

    # Now find the filenames - there can be multiple files with the same MSGID
    notmuch search --output=files ${m} | \
        while read f; do
            [[ -n ${DEBUG} ]] && echo "... file is: $f"

            TAGS=""

	    #####
	    # Add in the reserved tags
	    TAGS="${reserved_TAGS} ${TAGS}"

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
            [[ -n ${DEBUG} ]] && echo "... tags: >>${TAGS}<<"

            if [ "${TAGS}" != "+" ] && [ ! -z "${TAGS}" ]; then
                echo "${TAGS} -- ${m}" >> ${TMPFILE}
            fi

        done
    if [ $count -ge ${BATCH_SIZE} ]; then
	[[ -n ${DEBUG} ]] || echo "Applying"
        count=0
	count_batch=$(expr ${count_batch} + 1)
        batch_apply_tags
    fi
done

# Apply what's left...
[[ -n ${DEBUG} ]] || echo "Applying"
batch_apply_tags

${_E} mv -f ${TMPFILE}.lastrun ${LAST_RUN}

${_E} rm -f ${TMPFILE}*

echo "Done!"
#echo "\nDon't forget to remove 'new' tag."
