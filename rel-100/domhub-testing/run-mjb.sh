#!/bin/bash

#
# run-mjb.sh
#
function atexit() {
	rm -f /tmp/run-mjb.$$.*
}
trap atexit EXIT

if (( $# == 0 )); then
	results="/tmp/run-mjb.$$.mjb"
	echo "run-mjb: using temporary results file ${results}"
elif (( $# != 1 )); then
	echo "usage: run-mjb [results-file]"
	exit 1
else
	results=$1
fi

#
# convert results to absolute path so we can cd...
#
if ! echo ${results} | grep '^/' >& /dev/null; then
	results="`pwd`/${results}"
fi

#
# change to install directory...
# 
cd /usr/local/share/domhub-testing

#
# run mjb.sh
#
echo "run-mjb: power cycling..."
(off all && on all) >& /dev/null

doms=`find /proc/driver/domhub -name is-communicating -exec cat {} \; |
	awk '{ print $2 $4 $6; }'`

if (( ${#doms} == 0 )); then
	echo "run-mjb: no communicating doms found..."
	exit 1
fi

echo "run-mjb: running mjb, check back in 6 hours..."
if ! ./mjb.sh -h 6 all > ${results}; then
	echo "run-mjb: mjb data collection failed..."
	exit 1
fi

echo "run-mjb: analyzing results file: ${results}"
if ! ./results-qry.sh ${results} all; then
	echo "run-mjb: test failed"
	exit 1
fi

echo "run-mjb: turning off doms..."
off all
