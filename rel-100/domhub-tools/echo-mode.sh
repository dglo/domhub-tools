#!/bin/bash

#
# echo-mode.sh, put doms into echo mode...
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

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
	echo "usage: `basename $0` (all)|(CWD ...)"
	exit 1
fi

doms=`getDomList $*`

watchdogpid=0
pidlist=""
function atexit () {
    rm -f /tmp/em.$$.*
    for pid in ${pidlist}; do massacre ${pid}; done
    if (( ${watchdogpid} != 0 )); then kill ${watchdogpid}; fi
}
trap atexit EXIT

#
# doms -> iceboot
#
iceboot -q ${doms} >& /dev/null

#
# all doms are now in iceboot...
#
for dom in ${doms}; do
    ( printf 'send "echo-mode\r"\nexpect "echo-mode"\n' |
       se ${dom} >& /dev/null ) &
    echo $!
done > /tmp/em.$$.pids

pidlist=`cat /tmp/em.$$.pids | tr '\n' ' '`
( sleep 7; massacre ${pidlist} ) & watchdogpid=$!

for pid in ${pidlist}; do
    wait ${pid}
done
pidlist=""
kill ${watchdogpid}
watchdogpid=0
wait
