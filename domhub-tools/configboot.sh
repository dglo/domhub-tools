#!/bin/bash

#
# configboot.sh, move all doms that are talking into iceboot.
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

if (( $# < 1 )); then
    echo "usage: $0 all|(spec ...)"
    echo "  where spec is: card pair dom (e.g. 00A)"
    exit 1
fi

doms=`getDomList $*`

#
# deal with cleanup...
#
pidlist=""
watchdogpid=0
function atexit () {
    rm -f /tmp/cb.$$.*
    for pid in ${pidlist}; do
        kill ${pid}
    done
    if (( ${watchdogpid} != 0 )); then
        kill ${watchdogpid}
    fi
}
trap atexit EXIT

#
# make list of doms for which we need to transition...
#
domstate ${doms} | grep -v ' configboot$' | \
    awk '{ if (NF==2) print $0; }' > /tmp/cb.$$.state

if (( `wc -l /tmp/cb.$$.state | awk '{ print $1; }'` > 0 )); then
    #
    # get doms not in iceboot...
    #
    nibdoms=`grep -v ' iceboot$' /tmp/cb.$$.state | awk '{ print $1; }' | \
        tr '\n' ' '`

    if (( ${#nibdoms} > 0 )); then
        iceboot ${nibdoms} >& /dev/null
    fi

    #
    # now we're all in iceboot...
    #
    for dom in `awk '{ print $1; }' /tmp/cb.$$.state`; do
        ( printf 'send "boot-serial reboot\r"\nexpect "^# "\n' | \
	    se ${dom} >& /dev/null ) & echo $!
    done > /tmp/cb.$$.pids

    pids=`cat /tmp/cb.$$.pids | tr '\n' ' '`
    pidlist="${pids}"
    ( sleep 10; massacre ${pids} >& /dev/null ) & watchdogpid=$!
    for pid in ${pids}; do
         wait ${pid}
         if (( ${#status} > 127 )); then
             echo "configboot: TIMEOUT moving to configboot from iceboot"
         fi
    done
    pidlist=""
    rm -f /tmp/cb.$$.pids
    kill ${watchdogpid}
    watchdogpid=0
fi

# for compatibility...
domstate `echo ${doms} | sed 's/:[^ ]*//g'` | \
    awk '{ if (NF==2) print $1 " in " $2; else print $0; }'

