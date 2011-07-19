#!/bin/bash

minmax=0
while /bin/true; do
    if (( $# == 0 )); then break; fi

    if (( $1 == "-m" )); then 
	minmax=1
        shift
    else
	echo "usage: `basename $0` [-m]"
	exit 1
    fi
done

#
# tcal.sh, analyze a time calibration file in
# kalle format...
#
gawk -f /usr/local/share/domhub-tools/tcal.awk | \
	gawk -f /usr/local/share/domhub-tools/tcal-calc.awk | \
	dc > /tmp/rt-times.$$

if (( $minmax != 0 )); then
    min=`sort -n /tmp/rt-times.$$ | sed -n 1p`
    max=`sort -r -n /tmp/rt-times.$$ | sed -n 1p`
fi

avg=`awk '{ sum += $1; n++; } END { print 1.0*sum/n; }' /tmp/rt-times.$$`
dev=`awk -vavg=${avg} '{ sum +=  ($1 - avg)*($1 - avg); n++; } \
	END { print sqrt(sum/(n-1)); }' /tmp/rt-times.$$`

rm -f /tmp/rt-times.$$
echo ${avg} ${dev} ${min} ${max}

