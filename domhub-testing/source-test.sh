#!/bin/bash

#
# source-test.sh, source data on the dom, does blocking
# work on the dom?
#
# output: procfile_dom_id iceboot_dom_id
# 
source /usr/local/share/domhub-tools/common.sh
#exec 2> /dev/null

dom=$1

#
# reset com stats...
#
card=`getCard ${dom}`
pair=`getPair ${dom}`
d=`getDOM ${dom}`
procfile="/proc/driver/domhub/card${card}/pair${pair}/dom${d}/comstat"

echo 'reset' > ${procfile}

#
# source routine...
#
# send: type addr count send
# addr free zero
#
if ! printf 'send ": src-pkt 0 $01000000 596 send ;\r"\nexpect "^> "\n' |
        se ${dom} >& /dev/null; then
    exit 1
fi

#
# start sourcing...
#
if ! printf 'send "7000000 usleep 2250 0 ?DO src-pkt LOOP\r"\nsleep 1' | \
        se ${dom} >& /dev/null; then
    exit 2
fi

#
# sink data...
#
#res=`./sink $dom`
et=`/usr/bin/time \
    dd of=/dev/null if=/dev/dhc${card}w${pair}d${d} bs=4096 count=2250 2>&1 | \
    sed -n '3p' | awk '{ print $3; }' | tr -d '[a-z]' | tr ':' ' ' | tr '.' ' '`
etms=`echo ${et} | awk '{ print $1 * 60 * 1000 + $2 * 1000 + $3 * 10; }'`

if (( $? != 0 )); then
    exit 4
fi

#
# does the prompt come back?
#
if ! printf 'send "\r"\nexpect "^> "\n' | se ${dom} >& /dev/null; then
    exit 3
fi

let v=$(( 2250 * 596 ))
#
# dom [# messages] [# bytes] [elapsed time]
#
retx=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | awk '/^RESENT / { print $2; }
'`
err=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | awk '/^BADPKT / { print $2; }'
`
echo ${dom} 2250 ${v} ${etms} ${retx} ${err}

