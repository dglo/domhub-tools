#!/bin/bash

#
# results-qry.sh, query results in a mjb run...
#
if (( $# < 2 )); then
    echo "usage: `basename $0` [-q] dbfile (all|tests...)"
    exit 1
fi

function atexit() { rm -f /tmp/resq.$$.*; }
trap atexit EXIT

#
# deal with command line options...
#
verbose=0
while /bin/true; do
	if [[ $1 == "-v" ]]; then
		shift
		verbose=1
	else
		break
	fi
done	

function inform() {
    local nc=`printf '%s' "$1" | wc -c | awk '{ print $1;}'`
    printf '%s ' "$1"
    local i
    for ((i=0; i<70-${nc}; i++)); do printf '.'; done
    printf ' '
}

#
# check for any errors...
#
inform 'Check for Errors'
if grep 'ERROR' $1 >& /tmp/resq.$$.err; then
    echo "FAIL"
    awk '{ print "FAIL> " $0; }' /tmp/resq.$$.err
    exit 1
fi
echo "pass"

#
# get list of tests in this run...
#
awk '{ print $1; }' $1 | sort | uniq > /tmp/resq.$$.tests

#
# expand list of tests for which to get results...
#
dbfile=$1
shift
if [[ $1 == "all" ]]; then
     tests=`lessecho *-results.sh | tr ' ' '\n' | sed 's/\-results\.sh$//1'`
else
     tests="$*"
fi

#
# run tests...
#
ret=0
for test in ${tests}; do
    inform "Checking ${test}"
    # is this a real test?
    if grep "^${test}\$" /tmp/resq.$$.tests >& /dev/null; then
        filenm="/tmp/resq.$$.filenm"
        grep "^${test} " ${dbfile} > ${filenm}
    else
	echo "n/a"
	continue
    fi
    if ! DBFILE=$1 ./${test}-results.sh ${filenm} >& /tmp/resq.$$.out; then
        echo "FAIL"
        awk '{ print "FAIL> " $0; }' /tmp/resq.$$.out
	ret=1
    else
        echo "pass"
        if (( ${verbose} > 0 )); then
    	    awk '{ print "   " $0 }' /tmp/resq.$$.out
        fi
    fi 
done

exit $ret
