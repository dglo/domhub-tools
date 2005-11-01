#!/bin/bash

#
# tcal-test.sh, short tcal test, assume doms are
# not in configboot...
#
# run time is about 20-30s, output is: 
#   dom round_trip_time(ns) round_trip_rms(ns) dom_tx_rx_time(clocks) 
#     min_round_trip_time max_round_trip_time
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

dom=$1
tmpf=`mktemp /tmp/tct-XXXXXX`
function atexit() {
    rm -f ${tmpf}
}
trap atexit EXIT

#
# usage...
#
if (( $# != 1 )); then
   nm=`basename $0`
   echo "usage: ${nm} CWD"
   exit 1
fi

if ! tcalcycle -n 1000 ${dom} > ${tmpf}; then
    echo "`basename $0`: unable to run tcalcycle..."
    exit 1
fi 

clks=`egrep '^dom_[rt]x_time' ${tmpf} | sed -n '1,2p' | \
    awk '{ print $2; } END { print " - p q"}' | dc`

tcal-kalle ${tmpf} | \
    awk -vdom=${dom} -vclks=${clks} '{ print dom " " $0 " " clks; }'

rm -f ${tmpf}
trap "" EXIT
