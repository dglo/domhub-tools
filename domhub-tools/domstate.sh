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
function atexit () { 
    if (( ${#pidlist} > 0 )); then
        massacre ${pidlist}
    fi
    rm -f /tmp/ds.$$.*
}
trap atexit EXIT

if (( $# < 1 )); then
    echo "usage: $0 (CWD ...)|all"
    exit 1
fi

doms=`getDomList $*`

if (( ${#doms} == 0 )); then
    exit 0
fi

if [[ -d /proc/dor ]]; then
    cat /proc/dor/[0-7]/dom-status | sort -k 1 > /tmp/ds.$$.status
    doms=`echo ${doms} | tr ' ' '\n' | sort | \
	join -1 1 -2 1 - /tmp/ds.$$.status | \
	awk \
	'/^[0-7][0-3][AB] communicating no-hw-timeout closed/ { print $1; }' \
	| tr '\n' ' ' | sed 's/ $//1'`

    #
    # check for known responses...
    #
    # FIXME: check for stfserv OK string...
    #
    for dom in ${doms}; do
        ( printf 'send "\r"\nexpect "^((# )|(> )|ERR)"\n' |
	    se ${dom} | tr -d '\r' > /tmp/ds.$$.${dom}.out ) & 
	printf '%d:%s\n' $! ${dom}
    done > /tmp/ds.$$.pids
    pidlist=`cat /tmp/ds.$$.pids | sed 's/:.*$//1'`
    wait-till-dead 5000 ${pidlist}

    for pid in `cat /tmp/ds.$$.pids`; do
	dom=`echo ${pid} | sed 's/^.*://1'`
	
	if grep '^# ' /tmp/ds.$$.${dom}.out >& /dev/null; then
	    echo "${dom} configboot"
	elif grep '^> ' /tmp/ds.$$.${dom}.out >& /dev/null; then
	    echo "${dom} iceboot"
        else
	    echo "${dom} busy"
	fi
    done

    rm -f /tmp/ds.$$.*
    trap "" EXIT

    exit 0
fi

#
# take care of easy case...
#
# FIXME: this is _totally_ broken (e.g. what is the output format?)...
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

wait-till-dead 5000 ${pidlist}

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

pidlist=""
rm -f /tmp/ds.$$.*
trap "" EXIT

exit 0
