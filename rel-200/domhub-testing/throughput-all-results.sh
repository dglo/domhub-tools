#!/bin/bash

source throughput-common.sh
source results-common.sh

function atexit () {
    rm -f /tmp/thrall.$$.doms
}
trap atexit EXIT

#
# throughput-all-results.sh, get results of throughput
# tests on all doms...
#

#
# FIXME: for all doms, select err and retx and criterion...
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
sigma=92
mean=46050
pdoms=`paired-doms`
for dom in ${pdoms}; do
	cl=`printf '$3 ~ /^%s$/ { print $0; }' $dom`
	awk "${cl}" $1 | awk -vmean=${mean} -vsigma=${sigma} \
		'{ if (NF==12) print $4, mean, sigma, "3 * - - p"; }' $1 | \
		dc | sed 's/\..*$//1' | sort -n | uniq > \
		/tmp/thrall.$$.pslowest

        if (( `wc -l /tmp/thrall.$$.pslowest | awk '{ print $1; }'` > 0 )); then
            if (( `head -1 /tmp/thrall.$$.pslowest` < 0 )); then
	        echo "throughput-all: paired dom ${dom} is too slow"
	        exit 1
            fi
        fi
done

sigma=14
mean=89919
udoms=`unpaired-doms`
for dom in ${udoms}; do
        cl=`printf '$3 ~ /^%s$/ { print $0; }' $dom`
        awk "${cl}" $1 | awk -vmean=${mean} -vsigma=${sigma} \
                '{ if (NF==12) print $4, mean, sigma, "3 * - - p"; }' | \
		dc | sed 's/\..*$//1' | sort -n | uniq > \
		/tmp/thrall.$$.uslowest
        if (( `wc -l /tmp/thrall.$$.uslowest | awk '{ print $1; }'` > 0 )); then
            if (( `head -1 /tmp/thrall.$$.uslowest` < 0 )); then
                echo "throughput-all: unpaired dom ${dom}, is too slow"
                exit 1
            fi
        fi
done

#
# check echo test error count
#
if (( `awk '{ print $5; }' $1 | sort -n -r | uniq | sed -n '1p'` > 0 )); then
	echo "throughput-all: too many echo test errors"
	exit 1
fi

#
# check for crc errors...
#
if (( `awk '{ print $7; }' $1 | sort -n -r | uniq | sed -n '1p'` > 100 )); then
	echo "throughput-all: too many crc errors"
	exit 1
fi

#
# check for retxs...
#
if (( `awk '{ print $6; }' $1 | sort -n -r | uniq | sed -n '1p'` > 0 )); then
	echo "throughput-all: too many retxs"
	exit 1
fi

