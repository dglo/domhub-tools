#!/bin/bash

#
# tcal.sh, analyze a time calibration file in
# kalle or john's format...
#

#
# handle options...
#
alg="centroid"
while /bin/true; do
    if [[ $1 == "-x" ]]; then
       alg="xover"
       shift
    elif [[ $1 == "-c" ]]; then
       alg="centroid"
       shift
    else
       break
    fi
done

if (( $# != 1 )); then
    echo "usage: $0 tcalfile"
    exit 1
fi

function atexit() {
    rm -f /tmp/tcal.sh.$$.*
}
trap atexit EXIT

rt-times-xover() {
    # dorf domf dor_tx dor_rx dom_tx dom_rx
    awk '$1 ~ /^dor_[0-9][0-9]$/ { print $2; }' $1 | \
        ./xovr > /tmp/tcal.sh.$$.dorf
    awk '$1 ~ /^dom_[0-9][0-9]$/ { print $2; }' $1 | \
        ./xovr > /tmp/tcal.sh.$$.domf
    awk '$1 ~ /^dor_tx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dor_tx
    awk '$1 ~ /^dor_rx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dor_rx
    awk '$1 ~ /^dom_tx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dom_tx
    awk '$1 ~ /^dom_rx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dom_rx

    paste -d ' ' /tmp/tcal.sh.$$.dorf /tmp/tcal.sh.$$.domf \
        /tmp/tcal.sh.$$.dor_tx /tmp/tcal.sh.$$.dor_rx \
        /tmp/tcal.sh.$$.dom_tx /tmp/tcal.sh.$$.dom_rx | rtcalc
}

rt-times-centroid-old() {
    gawk -f /usr/local/share/domhub-tools/tcal.awk $1 | \
	gawk -f /usr/local/share/domhub-tools/tcal-calc.awk | \
	dc
}

rt-times-centroid() {
    gawk -f /usr/local/share/domhub-tools/tcal.awk $1 | rtcalc
}

analyze-kalle() {
    if [[ $alg == "centroid" ]]; then
	rt-times-centroid $1 > /tmp/tcal.sh.$$.rt-times
    elif [[ $alg == "xover" ]]; then
        rt-times-xover $1 > /tmp/tcal.sh.$$.rt-times
    else
        echo "invalid algorithm: $alg"
        exit 1
    fi

    avg=`awk '{ sum += $1; n++; } END { print 1.0*sum/n; }' \
        /tmp/tcal.sh.$$.rt-times`
    dev=`awk -vavg=${avg} '{ sum +=  ($1 - avg)*($1 - avg); n++; } \
	END { print sqrt(sum/(n-1)); }' /tmp/tcal.sh.$$.rt-times`

    echo ${avg} ${dev}
}

if `head -1 $1 | egrep -q '^DOM_[0-7][ab]_TCAL_round_trip_[0-9][0-9][0-9][0-9][0-9][0-9]$'`; then
    # kalle format
    analyze-kalle $1
else
    # johnj format
    awk -f /usr/local/share/domhub-tools/tcal-cvt.awk $1 > /tmp/tcal.sh.$$
    analyze-kalle /tmp/tcal.sh.$$
fi



