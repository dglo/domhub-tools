#!/bin/bash

#
# domstate.sh, attempt to determine dom state...
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

#
# cleanup...
#
pidlist=""
watchdogpid=0
function atexit () { 
    rm -f /tmp/ds.$$.*
    if (( ${#pidlist} > 0 )); then
        massacre ${pidlist}
    fi
}
trap atexit EXIT

if (( $# < 1 )); then
    echo "usage: $0 (CWD ...)|all"
    exit 1
fi

doms=`getDomList $*`

#
# take care of easy case...
#
for dom in ${doms}; do
    if [[ ${dom} != "sim" ]]; then
        card=`echo $dom | awk '{ print substr($0, 1, 1); }'`
        wp=`echo $dom | awk '{ print substr($0, 2, 1); }'`
        d=`echo $dom | awk '{ print substr($0, 3, 1); }'`
        procpath="/proc/driver/domhub"
        cwdpath="${procpath}/card${card}/pair${wp}/dom${d}"

        if ! [[ -f ${cwdpath}/is-communicating ]]; then
            echo "${dom} invalid"
            continue
        fi

        if ! cat ${procpath}/card${card}/pair${wp}/pwr | grep on > /dev/null; \
            then
            echo "${dom} off"
            continue
        fi

        if cat ${cwdpath}/is-communicating | grep NOT > /dev/null; then
            echo "${dom} uncommunicative"
            continue
        fi
    fi

    echo ${dom}
done > /tmp/ds.$$.doms

for dom in `cat /tmp/ds.$$.doms`; do
    #
    # check for known responses...
    #
    ( printf 'send "\r"\nexpect "^((# )|(> )|ERR)"\n' | \
        se ${dom} | tr -d '\r' > /tmp/ds.$$.${dom}.out ) & 
    printf '%d:%s\n' $! ${dom}
done > /tmp/ds.$$.pids

pidlist=`awk -vFS=':' '{ print $1; }' /tmp/ds.$$.pids | tr '\n' ' '`
pidinfo=`cat /tmp/ds.$$.pids | tr '\n' ' '`
if (( ${#pidlist} > 0 )); then
    ( sleep 5; massacre ${pidlist} >& /dev/null ) & watchdogpid=$!

    for pids in ${pidinfo}; do
        pid=`echo ${pids} | awk -vFS=':' '{ print $1; }'`
        dom=`echo ${pids} | awk -vFS=':' '{ print $2; }'`
        wait $pid
        status=$?
        if (( ${status} != 0 )); then
            echo "${dom} busy"
        elif grep '^# ' /tmp/ds.$$.${dom}.out >& /dev/null; then
            echo "${dom} configboot"
        elif grep '^> ' /tmp/ds.$$.${dom}.out >& /dev/null; then
            echo "${dom} iceboot"
        elif grep '^ERR' /tmp/ds.$$.${dom}.out >& /dev/null; then
            echo "${dom} stfserv"
        else
            echo "${dom} unknown (internal error):"
            awk -vdom=${dom} '{ print dom ": " $0; }' /tmp/ds.$$.${dom}.out
        fi
    done
    kill ${watchdogpid} >& /dev/null
    watchdogpid=0
    pidlist=""
fi

