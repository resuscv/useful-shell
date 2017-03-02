#!/bin/bash
#
# Some useful functions
# See  http://www.kfirlavi.com/blog/2012/11/14/defensive-bash-programming

readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink -m $(dirname $0))
readonly ARGS="$@"


is_dir() {
    local dir=$1

    [[ -d $dir ]]
}


is_file() {
    local file=$1

    [[ -f $file ]]
}


is_empty() {
    local var=$1

    [[ -z $var ]]
}


is_not_empty() {
    local var=$1

    [[ -n $var ]]
}


WantDebugging() {
    # I use something in main() like:
    #    _E=$(WantDebugging ${DEBUG})
    local debug=$1

    is_not_empty ${debug} \
	&& echo "echo"
}


tic() {
    date +"%s"
}


toc() {
    local desc=$1
    local date1=$2
    local date2=$(tic)

    echo "  \__ ${desc} took: $(date -u -d @"$(($date2-$date1))" +'%-Mm %-Ss')"
}


fatal() {
    local exitcode=$1; shift
    local desc=$@

    echo ${desc}
    echo "Exiting with error code  ${exitcode}"
    exit ${exitcode}
}
