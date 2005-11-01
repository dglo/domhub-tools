#!/bin/bash

#
# quiet-test.sh, quiet dom, is it really quiet?
#
# output: nbytes
# 
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

cmdpid=0
function atexit () { 
    rm -f /tmp/qt.$$.*;
    if (( ${cmdpid} != 0 )); then
        kill ${cmdpid}
    fi
}
trap atexit EXIT

dom=$1

dd if=`getDev ${dom}` of=/tmp/qt.$$.out count=1000 bs=4096 >& /dev/null &
cmdpid=$!

sleep 60
kill ${cmdpid}
wait ${cmdpid}
cmdpid=0

echo ${dom} `wc -c /tmp/qt.$$.out | awk '{ print $1; }'`
