#!/bin/bash

#
# versions.sh, print dom versions...
#
source /usr/local/share/domhub-tools/common.sh
exec 2> /dev/null

doms=`getDomList $*`

function getVersions() {
    card=`echo $1 | awk '{ print substr($0, 1, 1); }'`
    pair=`echo $1 | awk '{ print substr($0, 2, 1); }'`
    ab=`echo $1 | awk '{ print substr($0, 3, 1); }'`
    if [[ -d /proc/driver/domhub ]]; then
	domid=`cat /proc/driver/domhub/card${card}/pair${pair}/dom${ab}/id | \
	    awk '{ print substr($9, 1, 12); }'`
#	echo "dom ${dom} card ${card} pair ${pair} ab ${ab} domid ${domid}"
	dorv=`cat /proc/driver/domhub/card${card}/fpga | \
	    awk '$1 ~ /^FREV$/ { print substr($2, 7, 2), substr($2, 9, 2); }'`
	dorn=`echo ${dorv} | awk '{ print $1; }'`
	dorc=`echo ${dorv} | awk '{ print $2; }'`
	let c=$(( 0x${dorc} ))
	let n=$(( 0x${dorc} ))
	dorv=`echo ${n} ${c} | awk '{ printf "%d%c", $1, $2 }'`
    else
	dorv=`cat /proc/dor/${card}/versions | awk '{ print $2; }'`
    fi

    icebootv=`printf 'send "reboot\r"\nexpect "^ Iceboot "\n' | \
	se ${dom} | grep '^ Iceboot ' | awk '{ print $4; }' | \
	sed 's/\.\.\..*$//1'`

    pldv=`printf 'send "pld-versions\r"\nexpect "^matches"\n' | \
	se ${dom} | awk '$0 ~ /^build number/ { print $3; }'`

    fpgav=`printf 'send "fpga-versions\r"\nexpect "^  supernova"\n' | \
	se ${dom} | awk '$0 ~ /^build number/ { print $3; }'`

    if [[ -d /proc/driver/domhub ]]; then
	drvr=`cat /proc/driver/domhub/revision | awk '{ print $1; }'`
    else
	drvr=`cat /proc/dor/${card}/versions | awk '{ print $1; }'`
    fi
    
    echo $1 ${dorv} ${icebootv} ${pldv} ${fpgav} ${drvr} ${domid} | tr -d '\r'
}

#
# put doms in iceboot...
#
doms=`iceboot ${doms} | awk '$3 ~ /^iceboot$/ { print $1; }'`
# echo " doms ${doms}" 
for dom in ${doms}; do
   getVersions ${dom} > /tmp/vr.$$.${dom}.out & printf '%d:%s\n' $! ${dom}
done > /tmp/vr.$$.pids

pids=`cat /tmp/vr.$$.pids`
rm -f /tmp/vr.$$.pids

for pid in ${pids}; do
    p=`echo $pid | awk -vFS=':' '{ print $1; }'`
    dom=`echo $pid | awk -vFS=':' '{ print $2; }'`
    if wait ${p}; then
	cat /tmp/vr.$$.${dom}.out
    else
        echo "error: " `cat /tmp/vr.$$.${dom}.out` 
    fi
    rm -f /tmp/vr.$$.${dom}.out
done

