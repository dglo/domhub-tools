#!/bin/bash

#
# run-test.sh, run a test...
#
# input: $1=test to run, $2=dom to run it on,
#   $3 is the filename of the file to touch when done...
#
# output:
#   exit status:
#      0 normal
#      1-99 returned from test run
#      100 duplicate test -- ignore
#      101 timeout
#      102 test not found
#      103 usage error
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /tmp/rt.$$.err

if (( $# != 3 )); then
    echo "usage: run-test test dom touchfile"
    exit 103
fi

timeout=`sed -n "/^$1 /p" tests.txt | awk '{ print $2; }'`
if (( ${#timeout} == 0 )); then
    # by default, you have 1 minute to finish...
    timeout=60
fi

#
# cleanup when done...
#
testpid=0
watchdogpid=0
donefile=$3
function atexit () {
    if (( $testpid != "0" )); then
	massacre ${testpid}	
    fi

    if (( $watchdogpid != "0" )); then
        massacre ${watchdogpid}
    fi

    rm -f /tmp/rt.$$.*

    touch ${donefile}
}
trap atexit EXIT

#
# get mode...
#
mode=`sed -n "/^$1 /p" tests.txt | awk '{ print $3; }'`
if (( ${#mode} == 0 )); then
    mode="iceboot"
fi

#
# set mode...
#
${mode} $2 >& /dev/null

#
# start test...
#
./$1-test.sh $2 & testpid=$!

#
# start watchdog...
#
( sleep ${timeout}; massacre ${testpid} ) & watchdogpid=$!

#
# wait for test...
#
wait ${testpid}
teststatus=$?
testpid=0
massacre ${watchdogpid}
wait ${watchdogpid}
watchdogpid=0

if (( ${teststatus} > 127 )); then
    exit 101
fi

if (( ${teststatus} > 0 )); then
    cat /tmp/rt.$$.err
fi

exit $teststatus

