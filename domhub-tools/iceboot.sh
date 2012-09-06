#!/bin/bash

#
# iceboot.sh, move all doms that are talking into iceboot.
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

#
# cleanup...
#
function atexit () {
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
cbpids=`for dom in ${cbdoms}; do 
    ( printf 'send "r"\nexpect "^ "\n' | se ${dom} >& /dev/null ) & echo $!
done`

#
# and now the rest...
#
rdoms=`egrep -v ' configboot$' /tmp/ib.$$.state | \
    awk '{ print $1; }' | tr '\n' ' '`
rpids=`if (( ${#rdoms} > 0 )); then
    softboot -q -f ${rdoms} >& /dev/null & echo $!
fi`

wait-till-dead 10000 ${cbpids} ${rpids} 

# for compatibility...
if (( ${quiet} == 0 )); then
    domstate ${doms} | \
        awk '{ if (NF==2) print $1 " in " $2; else print $0; }'
fi

atexit
trap "" EXIT
