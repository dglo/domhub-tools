#!/bin/bash

#
# tcal.sh, analyze a time calibration file in
# kalle or john's format...
#

if (( $# != 1 )); then
    echo "usage: $0 tcalfile"
    exit 1
fi

analyze-kalle() {
    gawk -f /usr/local/share/domhub-tools/tcal.awk $1 | \
	gawk -f /usr/local/share/domhub-tools/tcal-calc.awk | \
	dc > /tmp/rt-times.$$
    avg=`awk '{ sum += $1; n++; } END { print 1.0*sum/n; }' /tmp/rt-times.$$`
    dev=`awk -vavg=${avg} '{ sum +=  ($1 - avg)*($1 - avg); n++; } \
	END { print sqrt(sum/(n-1)); }' /tmp/rt-times.$$`

    rm -f /tmp/rt-times.$$
    echo ${avg} ${dev}
}

if `head -1 $1 | egrep -q '^DOM_[0-7][ab]_TCAL_round_trip_[0-9][0-9][0-9][0-9][0-9][0-9]$'`; then
    # kalle format
    analyze-kalle $1
else
    # johnj format
    rm -f /tmp/t.$$
    awk -f tcal-cvt.awk $1 > /tmp/t.$$
    analyze-kalle /tmp/t.$$
fi
