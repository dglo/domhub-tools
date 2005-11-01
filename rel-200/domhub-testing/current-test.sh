#!/bin/bash

#
# current-test.sh
#
# output: first_current avg_current rms_current max_dev_current
# 
source /usr/local/share/domhub-tools/common.sh
function atexit () { 
    rm -f /tmp/ct.$$.*; 
}
trap atexit EXIT

dom=$1
card=`getCard ${dom}`
pair=`getPair ${dom}`

if [[ -d /proc/driver/domhub ]]; then
    for ((i=0; i<1000; i++)); do
	cat /proc/driver/domhub/card${card}/pair${pair}/current | \
	    awk '{ print $7; }'
    done > /tmp/ct.$$.out
else
    for ((i=0; i<1000; i++)); do
	cat /proc/dor/${card}/wp-status | grep "^${card}${pair}" | \
	    awk '{ print $9; }'
    done > /tmp/ct.$$.out
fi

#
# calculate...
#
first=`sed -n '1p' /tmp/ct.$$.out`
avg=`sed '1!s/$/ +/1' /tmp/ct.$$.out | \
    awk '{ print $0; } END { print " 3 k 1000 / p"; }' | dc`

rms=`awk -vavg=${avg} \
    '{ print $1 " " avg " - 2 ^ ";  if (NR>1) print "+"; }' /tmp/ct.$$.out | \
    awk '{ print $0; } END { print " 3 k 999 / v p "; }' | dc`

maxd=`awk -vavg=${avg} \
    '{ print $1 " " avg " - 2 ^ p"; }' /tmp/ct.$$.out | dc | sort -r -n | \
    sed -n '1p' | awk '{ print $0 " v p"; }' | dc`

echo ${dom} ${first} ${avg} ${rms} ${maxd}

