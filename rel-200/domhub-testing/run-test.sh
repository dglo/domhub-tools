#!/bin/bash

#
# run-test.sh, run a test...
#
# input: $1=test to run, $2=dom to run it on,
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

if (( $# != 2 )); then
    echo "usage: run-test test dom"
    exit 103
fi

#
# get timeout value (in seconds)...
#
timeout=`sed -n "/^$1 /p" tests.txt | awk '{ print $2; }'`
if (( ${#timeout} == 0 )); then
    # by default, you have 1 minute to finish...
    timeout=60
fi

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
# FIXME: should this be more robust?
#
${mode} $2 >& /dev/null

#
# start test...
#
echo "run-test.sh: exec ./mjb-run-test ./$1-test.sh $2 ${timeout}" >> \
    run-test.log

exec ./mjb-run-test ./$1-test.sh $2 ${timeout}
