#!/bin/bash

#
# echo-test.sh:
#
#  dom nbytes seconds nretx ncrcerrs
#
source /usr/local/share/domhub-tools/common.sh
dom=$1

# reset comm stats...
card=`getCard ${dom}`
pair=`getPair ${dom}`
d=`getDOM ${dom}`

if [[ -d /proc/driver/domhub ]]; then
    procfile="/proc/driver/domhub/card${card}/pair${pair}/dom${d}/comstat"
else
    procfile="/proc/dor/${card}/dom-stats"
fi

echo 'reset' > ${procfile}

res=`./echo-test -n 500 -t 10000 ${dom}`

if (( $? > 0 )); then
    exit 1
fi

retx=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | awk '/^RESENT / { print $2; }'`
err=`cat ${procfile} | tr ' ' '\n' | tr '=' ' ' | awk '/^BADPKT / { print $2; }'`

echo ${res} ${retx} ${err}

