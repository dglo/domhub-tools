#!/bin/bash

source throughput-common.sh

function atexit () {
    rm -f /tmp/thrAB.$$.doms
}
trap atexit EXIT

#
# throughput-AB.sh, get results of throughput
# tests for A/B doms...
#

#
# FIXME: check interrupt, times stats -- interrupts, and times are
# (approx) per wire pair...
#

#
# for the paired doms
#
# we use 3*sigma for a cutoff (p value around 0.005)...
#
sigma=42
mean=86012
pdoms=`paired-doms`
for dom in ${pdoms}; do
	cl=`printf '$3 ~ /^%s$/ { print $0; }' $dom`
	awk "${cl}" $1 | awk -vmean=${mean} -vsigma=${sigma} \
		'{ if (NF==12) print $4, mean, sigma, "3 * - - p"; }' $1 | \
		dc | sed 's/\..*$//1' | sort -n | uniq > \
		/tmp/thrAB.$$.pslowest

        if (( `wc -l /tmp/thrAB.$$.pslowest | awk '{ print $1; }'` > 0 )); then
            if (( `head -1 /tmp/thrAB.$$.pslowest` < 0 )); then
	        echo "`basename $0`: paired dom ${dom} is too slow"
	        exit 1
            fi
        fi
done

sigma=13
mean=89923
udoms=`unpaired-doms`
for dom in ${udoms}; do
        cl=`printf '$3 ~ /^%s$/ { print $0; }' $dom`
        awk "${cl}" $1 | awk -vmean=${mean} -vsigma=${sigma} \
                '{ if (NF==12) print $4, mean, sigma, "3 * - - p"; }' | \
		dc | sed 's/\..*$//1' | sort -n | uniq > \
		/tmp/thrAB.$$.uslowest
        if (( `wc -l /tmp/thrAB.$$.uslowest | awk '{ print $1; }'` > 0 )); then
            if (( `head -1 /tmp/thrAB.$$.uslowest` < 0 )); then
                echo "`basename $0`: unpaired dom ${dom}, is too slow"
		cat /tmp/thrAB.$$.uslowest
                exit 1
            fi
        fi
done

#
# check echo test error count
#
if (( `awk '{ print $5; }' $1 | sort -n -r | uniq | sed -n '1p'` > 0 )); then
	echo "`basename $0`: too many echo test errors"
	exit 1
fi

#
# check for crc errors...
#
if (( `awk '{ print $7; }' $1 | sort -n -r | uniq | sed -n '1p'` > 1 )); then
	echo "`basename $0`: too many crc errors"
	exit 1
fi

#
# check for retxs...
#
if (( `awk '{ print $6; }' $1 | sort -n -r | uniq | sed -n '1p'` > 0 )); then
	echo "`basename $0`: too many retxs"
	exit 1
fi

