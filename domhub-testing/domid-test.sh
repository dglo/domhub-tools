#!/bin/bash

#
# domid-test.sh, do domids match -- are they valid -- are
# there any duplications?
#
# output: procfile_dom_id iceboot_dom_id
# 
source /usr/local/share/domhub-tools/common.sh
#exec 2> /dev/null
function atexit () { 
    rm -f /tmp/dit.$$.*; 
}
trap atexit EXIT

dom=$1
card=`getCard ${dom}`
pair=`getPair ${dom}`
d=`getDOM ${dom}`
domid=`cat /proc/driver/domhub/card${card}/pair${pair}/dom${d}/id | \
    awk '{ print $9; }'`
domidib=`printf 'send "domid type crlf type\r"\nexpect "^[0-9a-f]+[\r]*$"' | \
    se ${dom} | tr -d '\r' | egrep '^[0-9a-f]+$'`

echo ${dom} ${domid} ${domidib}

