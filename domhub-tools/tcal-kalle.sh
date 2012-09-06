#!/bin/bash


#
# tcal.sh, analyze a time calibration file in
# kalle format...
#

toolspath=/usr/local/share/domhub-tools
#toolspath=.
algorithm="xover"

while /bin/true; do
    if [[ $1 == "-x" ]]; then
       algorithm="xover"
       shift
    elif [[ $1 == "-c" ]]; then
       algorithm="centroid"
       shift
    else
       break
    fi
done

if (( $# != 1 )); then
    echo "usage: `basename $0` [-x|-c] tcal-file"
    exit 1
fi

rt-times-xover() {
    # dorf domf dor_tx dor_rx dom_tx dom_rx
    awk '$1 ~ /^dor_[0-9][0-9]$/ { print $2; }' $1 | \
        xovr > /tmp/tcal.sh.$$.dorf
    awk '$1 ~ /^dom_[0-9][0-9]$/ { print $2; }' $1 | \
        xovr > /tmp/tcal.sh.$$.domf
    awk '$1 ~ /^dor_tx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dor_tx
    awk '$1 ~ /^dor_rx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dor_rx
    awk '$1 ~ /^dom_tx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dom_tx
    awk '$1 ~ /^dom_rx_time$/ { print $2; }' $1 > /tmp/tcal.sh.$$.dom_rx

    paste -d ' ' /tmp/tcal.sh.$$.dorf /tmp/tcal.sh.$$.domf \
        /tmp/tcal.sh.$$.dor_tx /tmp/tcal.sh.$$.dor_rx \
        /tmp/tcal.sh.$$.dom_tx /tmp/tcal.sh.$$.dom_rx

}

#
# baseline is defined as samples 00-19...
#
# data are in file named by $1 -- baseline samples go to stdout...
#
function dorBaseline() {
    awk '$1 ~ /^dor_[01][0-9]$/ { print $2; }' $1
}

function domBaseline() {
    awk '$1 ~ /^dom_[01][0-9]$/ { print $2; }' $1
}

#
# calculate dor/dom baseline info: min max avg rms...
#
# compute the average value of samples
#
function avgSamples() {
    awk '{ sum += $1; n++; } END { printf "%.4f\n", 1.0*sum/n; }' $1
}

#
# compute stddev of samples...
#
function devSamples() {
    awk -vavg=$2 '{ sum +=  ($1 - avg)*($1 - avg); n++; } \
	END { printf "%.4f\n", sqrt(sum/(n-1)); }' $1
}

#
# compute minmax of samples...
#
function minMaxSamples() {
    sort -n $1 | sed -n -e '1p' -e '$p' | tr '\n' ' ' | sed 's/ $//1'
}

# compute baselines...
tfn=`mktemp /tmp/tcal-kalle-XXXXXX`
dorBaseline $1 > ${tfn}
avg=`avgSamples ${tfn}`
dorammd="${avg} `minMaxSamples ${tfn}` `devSamples ${tfn} ${avg}`"
domBaseline $1 > ${tfn}
avg=`avgSamples ${tfn}`
domammd="${avg} `minMaxSamples ${tfn}` `devSamples ${tfn} ${avg}`"

if [[ ${algorithm} == "centroid" ]]; then
    gawk -f ${toolspath}/tcal.awk $1 | rtcalc > ${tfn}
elif [[ ${algorithm} == "xover" ]]; then
    rt-times-xover $1 | rtcalc > ${tfn}
    rm -f /tmp/tcal.sh.$$.*
else
    echo "`basename $0`: invalid algorithm: ${algorithm}"
    rm /tmp/tcal.sh.*
    rm -f ${tfn}
    exit 1
fi

minmax=`minMaxSamples ${tfn}`
avg=`avgSamples ${tfn}`
dev=`devSamples ${tfn} ${avg}`
rm -f ${tfn}
echo ${avg} ${dev} ${minmax} ${dorammd} ${domammd}
