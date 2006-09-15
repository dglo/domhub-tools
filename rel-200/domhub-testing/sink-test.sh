#!/bin/bash

#
# sink-test.sh, sink data on the dom, does blocking
# work?
#
# output: procfile_dom_id iceboot_dom_id
# 
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

dom=$1
if [[ $2 == "" ]]; then
    pktsiz=64
else
    pktsiz=$2
fi

#
# reset com stats...
#
card=`getCard ${dom}`
pair=`getPair ${dom}`
d=`getDOM ${dom}`
if [[ -d /proc/driver/domhub ]]; then
   procfile="/proc/driver/domhub/card${card}/pair${pair}/dom${d}/comstat"
else
   procfile="/proc/dor/${card}/dom-stats"
fi

echo 'reset' > ${procfile}

#
# sink routine...
#
# rcv: type addr count
# addr free zero
#
if ! printf 'send ": sink-pkt rcv drop free drop drop ;\r"\nexpect "^> "\n' |
        se ${dom} >& /dev/null; then
    exit 1
fi

#
# start sinking...
#
count=20000
if ! printf 'send "${count} 0 ?DO sink-pkt LOOP\r"\nsleep 1\n' | \
        se ${dom} >& /dev/null; then
    exit 2
fi

#
# start sending -- capture elapsed time...
#
devfile=`getDev ${dom}`
et=`/usr/bin/time \
  dd if=/dev/zero of=${devfile} bs=${pktsiz} count=${count} 2>&1 | \
    sed -n '3p' | awk '{ print $3; }' | tr -d '[a-z]' | tr ':' ' ' | tr '.' ' '`
etms=`echo ${et} | awk '{ print $1 * 60 * 1000 + $2 * 1000 + $3 * 10; }'`

#
# does the prompt come back?
#
if ! printf 'send "\r"\nexpect "^> "\n' | se ${dom} >& /dev/null; then
    exit 3
fi

let v=$(( 20000 * ${pktsiz} ))
#
# dom [# messages] [# bytes] [elapsed time]
#
retx=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | awk '/^RESENT / { print $2; }
'`
err=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | awk '/^BADPKT / { print $2; }'
`
echo ${dom} 20000 ${v} ${etms} ${retx} ${err}

