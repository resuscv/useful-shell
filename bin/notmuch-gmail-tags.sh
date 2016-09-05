#!/bin/sh
# 
# Script to take Maildir(-type) files from a notmuch search and
# 1. extract the Gmail tags from X-Keywords
# 2. add them to the notmuch database
#
# INPUT is a messageID -- So use something like:
#   notmuch search --output=messages tag:GetGoogleTags | xargs notmuch-gmail-tags.sh


SELF=$(basename $0)
MSGIDs=$@

fatal() {
    echo "$SELF: fatal: $1" >&2
        [ -z $2 ] && exit 1
        exit $2
}

TMPFILE=$(mktemp) || fatal "mktemp failed"


# Set `DEBUG` environment to NOT run the tagging, but to simply collect the tags
[[ -n ${DEBUG} ]] && _E=echo


for m in ${MSGIDs}; do
    echo "Processing: $m"
    # Now find the filenames - there can be multiple files with the same MSGID
    notmuch search --output=files ${m} | \
	while read f; do
            # N.B. The following changes are made to tags:
	    #      1. Remove back slashes '\'
	    #      2. Spaces ' ' are replaced with underscores '_'
	    #      3. Tags starting '-' (with any number of following
	    #         spaces) have it removed
	    #      4. Tags are made lower case (I can't be bothered
	    #         hitting SHIFT)
            TAGS=$(sed '/^$/Q' "$f" | \
			  grep '^X-Keywords: ' | \
			  sed -e 's/^X-Keywords: /+/' \
			      -e 's/\\//g' \
			      -e 's/ /_/g' \
			      -e 's/,/ +/g' \
			      -e 's/+-_*/+/g' \
			  | \
			  tr '[:upper:]' '[:lower:]')
	    # Handle the case of no tags from 'X-Keywords'
            if [ "${TAGS}" == "+" ]; then
		TAGS=""
            fi
            TAGS="${TAGS} -GetGoogleTags"
	    echo "${TAGS} -- ${m}" >> ${TMPFILE}
	done
done

echo "-----\nNow we just batch apply the tags..."
${_E} notmuch tag --batch --input=${TMPFILE}
# and clean up after ourselves...
${_E} rm -f ${TMPFILE}
echo "Done!"
