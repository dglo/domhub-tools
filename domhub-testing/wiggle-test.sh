#!/bin/bash

#
# wiggle-test.sh
#
# output: nothing!
# 
source /usr/local/share/domhub-tools/common.sh

dom=$1
card=`getCard ${dom}`
pair=`getPair ${dom}`
d=`getDOM ${dom}`

printf 'send "no-comm wiggle\r"\nsleep 5\n' | se ${dom} >& /dev/null
sleep 60
echo 'reset' > \
	/proc/driver/domhub/card${card}/pair${pair}/dom${d}/is-communicating
if ! printf 'send "\r"\nexpect "^> "\n' | se ${dom} >& /dev/null; then
    exit 1
fi

echo ${dom}

