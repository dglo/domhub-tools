#!/bin/bash

#
# iceboot.sh, move all doms that are talking into iceboot.
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

#
# cleanup...
#
watchdogpid=0
function atexit () {
    if [[ -f /tmp/ib.$$.pids ]]; then
        for pids in `cat /tmp/ib.$$.pids`; do
            kill ${pids}
        done
    fi
    if (( ${watchdogpid} != 0 )); then
        /bin/kill ${watchdogpid}
    fi
    rm -f /tmp/ib.$$.* 
}
trap atexit EXIT

quiet=0
while /bin/true; do
    if [[ $1 == "-q" ]]; then
        quiet=1
    else
        break
    fi
    shift
done

if (( $# < 1 )); then
    echo "usage: $0 all|(spec ...)"
    echo "  where spec is: card pair dom (e.g. 00A)"
    exit 1
fi

doms=`getDomList $*`

#
# make a list of doms that we need to transition...
#
domstate ${doms} | grep -v ' iceboot$' | \
    awk '{ if (NF==2) print $0; }' > /tmp/ib.$$.state

#
# deal with configboot doms...
#
cbdoms=`grep ' configboot$' /tmp/ib.$$.state | awk '{ print $1; }' | \
   tr '\n' ' '`
for dom in ${cbdoms}; do 
    ( printf 'send "r"\nexpect "^ "\n' | se ${dom} >& /dev/null ) &
    echo $!
done > /tmp/ib.$$.pids

#
# deal with stfserv doms...
#
sdoms=`grep ' stfserv$' /tmp/ib.$$.state | awk '{ print $1; }' | tr '\n' ' '`
for dom in ${sdoms}; do
    ( printf 'send "REBOOT\r"\nexpect "^> "\n' | se ${dom} >& /dev/null ) &
    echo $!
done >> /tmp/ib.$$.pids

#
# and now the rest...
#
rdoms=`egrep -v ' ((stfserv)|(configboot))$' /tmp/ib.$$.state | \
    awk '{ print $1; }' | tr '\n' ' '`
if (( ${#rdoms} > 0 )); then
    softboot -q -f ${rdoms} >& /dev/null & echo $!
fi >> /tmp/ib.$$.pids

pids=`cat /tmp/ib.$$.pids | tr '\n' ' ' | sed 's/ $//1'`
( sleep 10; massacre ${pids} >& /dev/null ) & watchdogpid=$!
for pid in ${pids}; do
    wait ${pid}
done
rm -f /tmp/ib.$$.pids
/bin/kill -9 ${watchdogpid}
watchdogpid=0

# for compatibility...
if (( ${quiet} == 0 )); then
    domstate ${doms} | \
        awk '{ if (NF==2) print $1 " in " $2; else print $0; }'
fi

wait

