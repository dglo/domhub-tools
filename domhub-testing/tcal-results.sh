#!/bin/bash

#
# check tcal test results...
#
v=`awk '{ print $5; }' $1 | sort -n -r | sed -n 1p | sed 's/\..*//1'`
if (( "$v" > 4 )); then
	echo "tcal: round trip rms is too big: ${v}"
	exit 1
fi 

if (( `awk '{ print $8; }' $1 | sort -n | uniq | wc -l | awk '{ print $1; }'` \
      != 1 )); then
	echo "tcal: dom tx - rx clocks is not always the same"
	exit 1
fi

if (( `awk '{ print $8; }' $1 | sort -n | uniq` != 610 )); then
	echo "tcal: dom tx - rx clocks is not always 610"
	exit 1
fi


