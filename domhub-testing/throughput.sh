#!/bin/bash

#
# throughput.sh:
#
#  dom nbytes seconds nretx ncrcerrs sys-time user-time
#
source /usr/local/share/domhub-tools/common.sh
doms=`getDomList $*`

function atexit () {
    rm -f /tmp/thr.$$.*
}
trap atexit EXIT

function totalInterrupts () {
    ncpu=`cat /proc/interrupts | sed -n 1p | awk '{ print NF; }'`
    cat /proc/interrupts | egrep '^[ ]*[0-9]+\:' | \
        awk -vncpu=${ncpu} '{ for (i=0; i<ncpu; i++) print $(i+2); }' | \
        sed '1!s/$/ +/1' | awk '{ print $0; } END { print "p"; }' | dc
}

# collect baseline stats...
interrupts="`totalInterrupts` `sleep 30` `totalInterrupts`"
intrate=`echo "${interrupts} r - 1 k 30 / p" | dc`

# reset comm stats...
for dom in ${doms}; do
    card=`getCard ${dom}`
    pair=`getPair ${dom}`
    d=`getDOM ${dom}`
    if [[ -d /proc/driver/domhub ]]; then
	procfile="/proc/driver/domhub/card${card}/pair${pair}/dom${d}/comstat"
    else
	procfile="/proc/dor/${card}/dom-stats"
    fi
    echo 'reset' > ${procfile}
done

sints=`totalInterrupts`
if ! time -p ./echo-test -n 1000 ${doms} \
        1> /tmp/thr.$$.out 2> /tmp/thr.$$.times; then
    exit 1
fi

#
# compute throughput...
#
awk '{ print $2, $3, "1 k / p"}' /tmp/thr.$$.out | dc > /tmp/thr.$$.tp

eints=`totalInterrupts`
rtime=`sed -n 1p /tmp/thr.$$.times | awk '{ print $2; }'`
stime=`sed -n 3p /tmp/thr.$$.times | awk '{ print $2; }'`
sperc=`echo "$stime $rtime 4 k / 100 * p" | dc`
utime=`sed -n 2p /tmp/thr.$$.times | awk '{ print $2; }'`
uperc=`echo "$utime $rtime 4 k / 100 * p" | dc`
nintrate=`echo "${eints} ${sints} - 1 k ${rtime} / ${intrate} - p" | dc`

for dom in ${doms}; do
    retx=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | \
        awk '/^RESENT / { print $2; }'`
    err=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | \
        awk '/^BADPKT / { print $2; }'`

    echo `paste -d ' ' /tmp/thr.$$.out /tmp/thr.$$.tp | grep "^${dom} " | \
awk '{ print $1, $5, $4; }'` \
${retx} ${err} ${intrate} ${nintrate} \
${rtime} ${sperc} ${uperc}
done

