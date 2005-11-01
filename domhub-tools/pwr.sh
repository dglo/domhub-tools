#!/bin/bash

function usage() {
   echo "usage: `basename $0` on|off [cards wps]"
   exit 0
}

if (( $# == 0 )); then usage; fi

if (( $# == 1 )); then
    if [[ -d /proc/dor ]]; then
	wps=`cat /proc/dor/[0-7]/wp-status | \
	    awk '$3 ~ /^plugged$/ { print $1; }'`

	cards=`echo ${wps} | tr ' ' '\n' | sed 's/[0-3]$//1' | uniq`
	for card in ${cards}; do
	    cwp=`echo ${wps} | tr ' ' '\n' | grep "^${card}" | \
		sed 's/^[0-7]//1' | tr -d '\n'`
	    nwps="${nwps} ${card}:${cwp}"
	done
	wps=$nwps
    else
	$1 all
	exit 0
    fi
elif (( $# == 3 )); then
    cards=`echo $2 | sed 's/[0-7]/& /g' | sed 's/ $//1'`
    for card in ${cards}; do
	wps="${wps} ${card}:$3"
    done
else
    usage
fi

for wp in ${wps}; do
    card=`echo ${wp} | tr ':' ' ' | awk '{ print $1; }'`
    sel=`echo ${wp} | tr ':' ' ' | awk '{ print $2; }'`
    if [[ -d /proc/dor ]]; then
	echo $sel > /proc/dor/${card}/pwr-$1 & 
    else
	for pair in `echo ${sel} | sed 's/[0-3]/& /g'`; do
	    echo $1 > /proc/driver/domhub/card${card}/pair${pair}/pwr &
	done
    fi
done
wait
