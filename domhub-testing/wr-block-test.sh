#!/bin/bash

#
# wr-block-test.sh, test dor write blocking...
#
# push data to doms in echo mode, but don't read
# it back.  wait until the fifos are plugged and
# retx goes nuts, then stop pushing data, close the
# connection and try to reopen, how long does it
# take to reconnect...
#
source /usr/local/share/domhub-tools/common.sh
#exec 2> /dev/null

dom=$1

testpid=0
function atexit () {
    if (( ${testpid} != 0 )); then
        kill ${testpid}
    fi
}
trap atexit EXIT

#
# start them up...
#
dd if=/dev/zero of=`getDev $1` bs=64 count=10000 >& /dev/null & testpid=$!

#
# wait for queues to fill up...
#
sleep 30

#
# stop pushing data...
#
kill ${testpid}
wait ${testpid}
testpid=0

#
# measure reopen time...
#
starttm=`date '+%s'`
printf 'send "hi there"\nexpect "hi there"\n' | se ${dom} >& /dev/null
endtm=`date '+%s'`
let diff=$(( ${endtm} - ${starttm} ))
echo ${dom} ${diff}

